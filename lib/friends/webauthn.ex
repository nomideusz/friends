defmodule Friends.WebAuthn do
  @moduledoc """
  WebAuthn module for FIDO2/WebAuthn authentication using the wax library.

  This module handles:
  - Registration challenge generation
  - Registration response verification (attestation)
  - Authentication challenge generation
  - Authentication response verification (assertion)
  """

  alias Friends.Repo
  alias Friends.Social.WebAuthnCredential
  import Ecto.Query
  import Bitwise
  require Logger

  # Challenge expiry time in seconds (5 minutes)
  @challenge_timeout 300

  @doc """
  Get the Relying Party ID (domain name).
  This should match your domain in production.
  """
  def rp_id do
    Application.get_env(:friends, :webauthn_rp_id, "localhost")
  end

  @doc """
  Get the Relying Party name (display name).
  """
  def rp_name do
    Application.get_env(:friends, :webauthn_rp_name, "Friends")
  end

  @doc """
  Get the origin URL for WebAuthn verification.
  """
  def origin do
    Application.get_env(:friends, :webauthn_origin, "http://localhost:4000")
  end

  @doc """
  Generate a registration challenge for a new credential.
  Returns options to be sent to the browser's navigator.credentials.create()
  """
  def generate_registration_challenge(user) do
    challenge = :crypto.strong_rand_bytes(32)

    # Get existing credentials to exclude (prevent re-registration)
    existing_credentials = list_user_credentials(user.id)
    exclude_credentials = Enum.map(existing_credentials, fn cred ->
      %{
        type: "public-key",
        id: Base.url_encode64(cred.credential_id, padding: false),
        transports: cred.transports || []
      }
    end)

    %{
      challenge: Base.url_encode64(challenge, padding: false),
      rp: %{
        name: rp_name(),
        id: rp_id()
      },
      user: %{
        id: to_string(user.id),
        name: user.username,
        displayName: user.display_name || user.username
      },
      pubKeyCredParams: [
        %{type: "public-key", alg: -7},   # ES256 (ECDSA with P-256)
        %{type: "public-key", alg: -257}  # RS256 (RSASSA-PKCS1-v1_5)
      ],
      timeout: @challenge_timeout * 1000,
      attestation: "none",  # We don't need attestation for this use case
      excludeCredentials: exclude_credentials,
      authenticatorSelection: %{
        residentKey: "preferred",
        userVerification: "preferred"
      }
    }
  end

  @doc """
  Verify a registration response and extract the credential.
  Returns {:ok, credential_data} or {:error, reason}
  """
  def verify_registration(attestation_response, challenge, user_id) do
    with {:ok, client_data_json} <- decode_base64url(attestation_response["clientDataJSON"]),
         {:ok, attestation_object} <- decode_base64url(attestation_response["attestationObject"]),
         {:ok, credential_id} <- decode_base64url(attestation_response["id"]),
         :ok <- verify_client_data(client_data_json, challenge, "webauthn.create"),
         {:ok, auth_data} <- parse_attestation_object(attestation_object),
         {:ok, public_key_spki} <- extract_public_key(auth_data) do

      # Build credential data for storage
      credential_data = %{
        credential_id: credential_id,
        public_key: public_key_spki,
        sign_count: auth_data.sign_count,
        transports: attestation_response["transports"] || [],
        user_id: user_id
      }

      {:ok, credential_data}
    else
      {:error, reason} -> {:error, reason}
      error -> {:error, {:verification_failed, error}}
    end
  end

  @doc """
  Generate an authentication challenge for an existing user.
  Returns options to be sent to the browser's navigator.credentials.get()
  """
  def generate_authentication_challenge(user) do
    challenge = :crypto.strong_rand_bytes(32)

    credentials = list_user_credentials(user.id)

    allow_credentials = Enum.map(credentials, fn cred ->
      # Build credential descriptor
      base = %{
        type: "public-key",
        id: Base.url_encode64(cred.credential_id, padding: false)
      }

      # Only include transports if we have them - empty array causes Safari to
      # show "Hardware key" prompt instead of Face ID/Touch ID
      case cred.transports do
        nil -> base
        [] -> base
        transports -> Map.put(base, :transports, transports)
      end
    end)

    %{
      challenge: Base.url_encode64(challenge, padding: false),
      timeout: @challenge_timeout * 1000,
      rpId: rp_id(),
      userVerification: "preferred",
      allowCredentials: allow_credentials
    }
  end

  @doc """
  Verify an authentication assertion.
  Returns {:ok, credential} or {:error, reason}
  """
  def verify_authentication(assertion_response, challenge, user_id) do
    with {:ok, client_data_json} <- decode_base64url(assertion_response["clientDataJSON"]),
         {:ok, authenticator_data} <- decode_base64url(assertion_response["authenticatorData"]),
         {:ok, signature} <- decode_base64url(assertion_response["signature"]),
         {:ok, credential_id} <- decode_base64url(assertion_response["id"]),
         :ok <- verify_client_data(client_data_json, challenge, "webauthn.get"),
         {:ok, credential} <- get_credential(user_id, credential_id),
         :ok <- verify_rp_id_hash(authenticator_data),
         :ok <- verify_user_present(authenticator_data),
         :ok <- verify_signature(credential.public_key, authenticator_data, client_data_json, signature),
         {:ok, new_sign_count} <- verify_sign_count(authenticator_data, credential.sign_count) do

      # Update the credential's sign count and last used timestamp
      update_credential_usage(credential, new_sign_count)

      {:ok, credential}
    else
      {:error, reason} -> 
        Logger.error("[WebAuthn] Verification failed: #{inspect(reason)}")
        {:error, reason}
      error -> 
        Logger.error("[WebAuthn] Unexpected error: #{inspect(error)}")
        {:error, {:verification_failed, error}}
    end
  end

  # --- Private Helper Functions ---

  defp decode_base64url(nil), do: {:error, :missing_data}
  defp decode_base64url(data) when is_binary(data) do
    case Base.url_decode64(data, padding: false) do
      {:ok, decoded} -> {:ok, decoded}
      :error -> {:error, :invalid_base64}
    end
  end

  defp verify_client_data(client_data_json, expected_challenge, expected_type) do
    case Jason.decode(client_data_json) do
      {:ok, client_data} ->
        with :ok <- verify_type(client_data["type"], expected_type),
             :ok <- verify_challenge(client_data["challenge"], expected_challenge),
             :ok <- verify_origin(client_data["origin"]) do
          :ok
        end
      {:error, _} ->
        {:error, :invalid_client_data_json}
    end
  end

  defp verify_type(actual, expected) when actual == expected, do: :ok
  defp verify_type(_, _), do: {:error, :invalid_type}

  defp verify_challenge(actual, expected) do
    # The challenge in clientData is base64url encoded
    if actual == expected do
      :ok
    else
      {:error, :challenge_mismatch}
    end
  end

  defp verify_origin(actual_origin) do
    expected = origin()
    # Allow both with and without port for flexibility
    if String.starts_with?(actual_origin, expected) or
       actual_origin == String.replace(expected, ~r/:4000$/, "") do
      :ok
    else
      {:error, {:origin_mismatch, actual_origin, expected}}
    end
  end

  defp parse_attestation_object(attestation_object) do
    # CBOR decode the attestation object
    case CBOR.decode(attestation_object) do
      {:ok, decoded, _rest} when is_map(decoded) ->
        # CBOR libraries may use string keys, atom keys, or binary keys
        # Try all possibilities for "authData"
        auth_data = Map.get(decoded, "authData") ||
                    Map.get(decoded, :authData) ||
                    Map.get(decoded, "auth_data") ||
                    Map.get(decoded, :auth_data)

        case auth_data do
          nil -> {:error, {:missing_auth_data, Map.keys(decoded)}}
          %CBOR.Tag{tag: :bytes, value: data} when is_binary(data) -> parse_authenticator_data(data)
          data when is_binary(data) -> parse_authenticator_data(data)
          other -> {:error, {:unexpected_auth_data_type, inspect(other)}}
        end
      {:ok, other, _rest} ->
        {:error, {:unexpected_cbor_structure, inspect(other)}}
      {:error, reason} ->
        {:error, {:cbor_decode_failed, reason}}
    end
  rescue
    e -> {:error, {:cbor_decode_error, e}}
  end

  # Handle non-binary auth_data with better error messages
  defp parse_authenticator_data(nil), do: {:error, :nil_auth_data}
  defp parse_authenticator_data(%CBOR.Tag{tag: :bytes, value: data}) when is_binary(data) do
    parse_authenticator_data(data)
  end
  defp parse_authenticator_data(auth_data) when is_binary(auth_data) do
    # Authenticator data structure:
    # - rpIdHash (32 bytes)
    # - flags (1 byte)
    # - signCount (4 bytes, big-endian)
    # - attestedCredentialData (variable, if AT flag set)
    # - extensions (variable, if ED flag set)

    case auth_data do
      <<rp_id_hash::binary-size(32), flags::8, sign_count::32-big, rest::binary>> ->
        user_present = (flags &&& 0x01) != 0
        user_verified = (flags &&& 0x04) != 0
        attested_credential_data = (flags &&& 0x40) != 0

        result = %{
          rp_id_hash: rp_id_hash,
          flags: flags,
          user_present: user_present,
          user_verified: user_verified,
          sign_count: sign_count,
          raw: auth_data
        }

        if attested_credential_data do
          case parse_attested_credential_data(rest) do
            {:ok, cred_data} -> {:ok, Map.merge(result, cred_data)}
            error -> error
          end
        else
          {:ok, result}
        end

      _ ->
        {:error, :invalid_authenticator_data}
    end
  end

  defp parse_attested_credential_data(data) do
    # Attested credential data structure:
    # - aaguid (16 bytes)
    # - credentialIdLength (2 bytes, big-endian)
    # - credentialId (credentialIdLength bytes)
    # - credentialPublicKey (COSE key, CBOR encoded)

    case data do
      <<aaguid::binary-size(16), cred_id_len::16-big, rest::binary>> ->
        case rest do
          <<cred_id::binary-size(cred_id_len), cose_key_cbor::binary>> ->
            case CBOR.decode(cose_key_cbor) do
              {:ok, cose_key, _rest} ->
                {:ok, %{
                  aaguid: aaguid,
                  credential_id: cred_id,
                  cose_key: cose_key
                }}
              error ->
                {:error, {:cose_key_decode_failed, error}}
            end
          _ ->
            {:error, :invalid_credential_data}
        end
      _ ->
        {:error, :invalid_attested_credential_data}
    end
  rescue
    e -> {:error, {:parse_error, e}}
  end

  defp extract_public_key(%{cose_key: cose_key}) do
    # Convert COSE key to SPKI format for storage
    # COSE key types: 2 = EC2 (ECDSA), 3 = RSA
    kty = cose_key[1] || cose_key["1"]

    case kty do
      2 -> extract_ec_public_key(cose_key)
      3 -> extract_rsa_public_key(cose_key)
      _ -> {:error, {:unsupported_key_type, kty}}
    end
  end
  defp extract_public_key(_), do: {:error, :no_cose_key}

  defp extract_ec_public_key(cose_key) do
    # EC2 key structure:
    # -1 (crv): curve (1 = P-256, 2 = P-384, 3 = P-521)
    # -2 (x): x coordinate
    # -3 (y): y coordinate
    crv = cose_key[-1] || cose_key["-1"]
    x = cose_key[-2] || cose_key["-2"]
    y = cose_key[-3] || cose_key["-3"]

    if x && y do
      # Store as concatenated x || y for EC keys (raw format)
      # We'll also include the curve identifier
      public_key = %{
        type: :ec,
        curve: crv,
        x: x,
        y: y
      }
      {:ok, :erlang.term_to_binary(public_key)}
    else
      {:error, :invalid_ec_key}
    end
  end

  defp extract_rsa_public_key(cose_key) do
    # RSA key structure:
    # -1 (n): modulus
    # -2 (e): exponent
    n = cose_key[-1] || cose_key["-1"]
    e = cose_key[-2] || cose_key["-2"]

    if n && e do
      public_key = %{
        type: :rsa,
        n: n,
        e: e
      }
      {:ok, :erlang.term_to_binary(public_key)}
    else
      {:error, :invalid_rsa_key}
    end
  end

  defp verify_rp_id_hash(authenticator_data) do
    <<actual_rp_id_hash::binary-size(32), _rest::binary>> = authenticator_data
    expected_rp_id_hash = :crypto.hash(:sha256, rp_id())

    if actual_rp_id_hash == expected_rp_id_hash do
      :ok
    else
      {:error, :rp_id_hash_mismatch}
    end
  end

  defp verify_user_present(authenticator_data) do
    <<_rp_id_hash::binary-size(32), flags::8, _rest::binary>> = authenticator_data

    if (flags &&& 0x01) != 0 do
      :ok
    else
      {:error, :user_not_present}
    end
  end

  defp verify_signature(stored_public_key, authenticator_data, client_data_json, signature) do
    # The signed data is: authenticatorData || SHA-256(clientDataJSON)
    client_data_hash = :crypto.hash(:sha256, client_data_json)
    signed_data = authenticator_data <> client_data_hash

    # Decode the stored public key
    public_key = :erlang.binary_to_term(stored_public_key)

    case public_key do
      %{type: :ec, curve: crv, x: x, y: y} ->
        verify_ec_signature(crv, x, y, signed_data, signature)
      %{type: :rsa, n: n, e: e} ->
        verify_rsa_signature(n, e, signed_data, signature)
      _ ->
        {:error, :unknown_key_type}
    end
  rescue
    e -> {:error, {:signature_verification_error, e}}
  end

  defp verify_ec_signature(crv, x, y, data, signature) do
    # Map COSE curve to Erlang named curve
    curve = case crv do
      1 -> :secp256r1  # P-256
      2 -> :secp384r1  # P-384
      3 -> :secp521r1  # P-521
      _ -> nil
    end

    if curve do
      # Build the EC public key in Erlang format
      # The point is represented as {x, y} coordinates
      point = <<4>> <> x <> y  # Uncompressed point format
      ec_key = {:ECPoint, point, {:namedCurve, curve_oid(curve)}}

      # WebAuthn uses DER-encoded ECDSA signatures
      case :public_key.verify(data, :sha256, signature, ec_key) do
        true -> :ok
        false -> {:error, :invalid_signature}
      end
    else
      {:error, {:unsupported_curve, crv}}
    end
  rescue
    e -> {:error, {:ec_verify_error, e}}
  end

  defp curve_oid(:secp256r1), do: {1, 2, 840, 10045, 3, 1, 7}
  defp curve_oid(:secp384r1), do: {1, 3, 132, 0, 34}
  defp curve_oid(:secp521r1), do: {1, 3, 132, 0, 35}

  defp verify_rsa_signature(n, e, data, signature) do
    # Build RSA public key
    rsa_key = {:RSAPublicKey, :binary.decode_unsigned(n), :binary.decode_unsigned(e)}

    case :public_key.verify(data, :sha256, signature, rsa_key) do
      true -> :ok
      false -> {:error, :invalid_signature}
    end
  rescue
    e -> {:error, {:rsa_verify_error, e}}
  end

  defp verify_sign_count(authenticator_data, stored_sign_count) do
    <<_rp_id_hash::binary-size(32), _flags::8, sign_count::32-big, _rest::binary>> = authenticator_data

    # Sign count should be greater than stored value (protects against cloned authenticators)
    # Some authenticators always return 0, so we allow that
    if sign_count == 0 or sign_count > stored_sign_count do
      {:ok, sign_count}
    else
      {:error, :sign_count_not_increased}
    end
  end

  defp get_credential(user_id, credential_id) do
    case Repo.get_by(WebAuthnCredential, user_id: user_id, credential_id: credential_id) do
      nil -> {:error, :credential_not_found}
      credential -> {:ok, credential}
    end
  end

  defp list_user_credentials(user_id) do
    Repo.all(
      from c in WebAuthnCredential,
        where: c.user_id == ^user_id,
        order_by: [desc: c.last_used_at]
    )
  end

  defp update_credential_usage(credential, new_sign_count) do
    credential
    |> Ecto.Changeset.change(%{
      sign_count: new_sign_count,
      last_used_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  @doc """
  Store a verified credential in the database.
  """
  def store_credential(credential_data, name \\ nil) do
    attrs = Map.merge(credential_data, %{
      name: name || "Hardware Key",
      last_used_at: DateTime.utc_now()
    })

    %WebAuthnCredential{}
    |> WebAuthnCredential.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Delete a credential.
  """
  def delete_credential(user_id, credential_id) do
    case get_credential(user_id, credential_id) do
      {:ok, credential} -> Repo.delete(credential)
      error -> error
    end
  end

  @doc """
  List all credentials for a user.
  """
  def list_credentials(user_id), do: list_user_credentials(user_id)

  @doc """
  Check if a user has any credentials registered.
  """
  def has_credentials?(user_id) do
    Repo.exists?(from c in WebAuthnCredential, where: c.user_id == ^user_id)
  end
end
