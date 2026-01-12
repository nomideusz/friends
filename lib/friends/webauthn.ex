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

    exclude_credentials =
      Enum.map(existing_credentials, fn cred ->
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
        # ES256 (ECDSA with P-256)
        %{type: "public-key", alg: -7},
        # RS256 (RSASSA-PKCS1-v1_5)
        %{type: "public-key", alg: -257}
      ],
      timeout: @challenge_timeout * 1000,
      # We don't need attestation for this use case
      attestation: "none",
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

    allow_credentials =
      Enum.map(credentials, fn cred ->
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
         :ok <-
           verify_signature(
             credential.public_key,
             authenticator_data,
             client_data_json,
             signature
           ),
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

    # Get allowed Android APK key hashes from config
    allowed_android_origins = Application.get_env(:friends, :webauthn_android_origins, [])

    cond do
      # Standard web origin check
      String.starts_with?(actual_origin, expected) ->
        :ok

      # Allow without port for flexibility (e.g., http://localhost vs http://localhost:4001)
      actual_origin == String.replace(expected, ~r/:\d+$/, "") ->
        :ok

      # Android APK key hash origin check
      String.starts_with?(actual_origin, "android:apk-key-hash:") ->
        if actual_origin in allowed_android_origins do
          :ok
        else
          Logger.warning("[WebAuthn] Unknown Android origin: #{actual_origin}")
          {:error, {:origin_mismatch, actual_origin, expected}}
        end

      true ->
        {:error, {:origin_mismatch, actual_origin, expected}}
    end
  end

  defp parse_attestation_object(attestation_object) do
    # CBOR decode the attestation object
    case CBOR.decode(attestation_object) do
      {:ok, decoded, _rest} when is_map(decoded) ->
        # CBOR libraries may use string keys, atom keys, or binary keys
        # Try all possibilities for "authData"
        auth_data =
          Map.get(decoded, "authData") ||
            Map.get(decoded, :authData) ||
            Map.get(decoded, "auth_data") ||
            Map.get(decoded, :auth_data)

        case auth_data do
          nil ->
            {:error, {:missing_auth_data, Map.keys(decoded)}}

          %CBOR.Tag{tag: :bytes, value: data} when is_binary(data) ->
            parse_authenticator_data(data)

          data when is_binary(data) ->
            parse_authenticator_data(data)

          other ->
            {:error, {:unexpected_auth_data_type, inspect(other)}}
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
                {:ok,
                 %{
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
    x = unwrap_bytes(cose_key[-2] || cose_key["-2"])
    y = unwrap_bytes(cose_key[-3] || cose_key["-3"])

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
    n = unwrap_bytes(cose_key[-1] || cose_key["-1"])
    e = unwrap_bytes(cose_key[-2] || cose_key["-2"])

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

  defp unwrap_bytes(%CBOR.Tag{tag: :bytes, value: bytes}), do: bytes
  defp unwrap_bytes(bytes) when is_binary(bytes), do: bytes
  defp unwrap_bytes(_), do: nil

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
        verify_ec_signature(crv, unwrap_bytes(x), unwrap_bytes(y), signed_data, signature)

      %{type: :rsa, n: n, e: e} ->
        verify_rsa_signature(unwrap_bytes(n), unwrap_bytes(e), signed_data, signature)

      _ ->
        {:error, :unknown_key_type}
    end
  rescue
    e -> {:error, {:signature_verification_error, e}}
  end

  defp verify_ec_signature(crv, x, y, data, signature) do
    # Map COSE curve to Erlang named curve
    {curve, size} =
      case crv do
        # P-256
        1 -> {:secp256r1, 32}
        # P-384
        2 -> {:secp384r1, 48}
        # P-521 (ceil(521/8) = 66)
        3 -> {:secp521r1, 66}
        _ -> {nil, 0}
      end

    if curve && x && y do
      # Ensure exact coordinate size (pad if short, trim if long e.g. leading zeros)
      x_fixed = fix_coordinate_size(x, size)
      y_fixed = fix_coordinate_size(y, size)

      # Build the EC public key in Erlang format
      # Uncompressed point format
      point = <<4>> <> x_fixed <> y_fixed

      # Normalize signature to strict DER format
      # This handles both raw 64-byte signatures AND potentially malformed DER inputs
      signature_der = normalize_der(signature)

      # Try verification with OID first using public_key (high level)
      ec_key_oid = {:ECPoint, point, {:namedCurve, curve_oid(curve)}}

      try do
        case :public_key.verify(data, :sha256, signature_der, ec_key_oid) do
          true -> :ok
          false -> {:error, :invalid_signature}
        end
      rescue
        _e in ArgumentError ->
          # Fallback 1: public_key with atom curve (legacy)
          ec_key_atom = {:ECPoint, point, {:namedCurve, curve}}

          try do
            case :public_key.verify(data, :sha256, signature_der, ec_key_atom) do
              true ->
                :ok

              false ->
                # Fallback 2: Direct crypto.verify (low level)
                verify_crypto_fallback(curve, point, data, signature_der)
            end
          rescue
            _ -> verify_crypto_fallback(curve, point, data, signature_der)
          end
      end
    else
      {:error, {:unsupported_curve, crv}}
    end
  rescue
    e ->
      Logger.error("[WebAuthn] EC Verify crash: #{inspect(e)}")
      {:error, {:ec_verify_error, e}}
  end

  defp verify_crypto_fallback(curve, point, data, signature) do
    # crypto:verify(Algorithm, DigestType, Msg, Signature, Key)
    # Key for ECDSA is [Point, CurveParams]
    # Try with atom first, then OID fallback
    case :crypto.verify(:ecdsa, :sha256, data, signature, [point, curve]) do
      true ->
        :ok

      false ->
        case :crypto.verify(:ecdsa, :sha256, data, signature, [point, curve_oid(curve)]) do
          true -> :ok
          false -> {:error, :invalid_signature}
        end
    end
  rescue
    e ->
      Logger.error("[WebAuthn] crypto.verify crash: #{inspect(e)}")
      {:error, :invalid_signature}
  end

  defp normalize_der(signature) do
    # Try to decode the signature as DER sequence of two integers (R, S)
    # Then re-encode strictly to satisfy Erlang's picky crypto lib
    case decode_der_sequence(signature) do
      {:ok, r, s} ->
        # Re-encode strictly by normalizing R and S to 32 bytes then passing to raw_to_der
        r_32 = fix_coordinate_size(r, 32)
        s_32 = fix_coordinate_size(s, 32)
        raw_to_der(r_32 <> s_32)

      _ ->
        # If decode fails, check if it's already a raw 64-byte signature
        if byte_size(signature) == 64 do
          raw_to_der(signature)
        else
          signature
        end
    end
  end

  # Relaxed matching: allow rest to be larger than len (ignore trailing bytes)
  defp decode_der_sequence(<<0x30, len, rest::binary>>) when byte_size(rest) >= len do
    # Take exactly len bytes for the sequence content
    sequence_content = binary_part(rest, 0, len)

    with {:ok, r, rest_s} <- decode_der_integer(sequence_content),
         {:ok, s, _trailing} <- decode_der_integer(rest_s) do
      {:ok, r, s}
    else
      _ -> :error
    end
  end

  defp decode_der_sequence(_), do: :error

  defp decode_der_integer(<<0x02, len, val::binary-size(len), rest::binary>>) do
    {:ok, val, rest}
  end

  defp decode_der_integer(_), do: :error

  defp raw_to_der(<<r::binary-size(32), s::binary-size(32)>>) do
    # Convert raw 64-byte signature (R|S) to ASN.1 DER
    # Integers must be positive, so prepend 0x00 if MSB is 1
    enc_r = der_integer(r)
    enc_s = der_integer(s)

    # Sequence tag (0x30) + length + R + S
    content = enc_r <> enc_s
    <<0x30, byte_size(content)>> <> content
  end

  defp raw_to_der(sig), do: sig

  defp der_integer(bin) do
    # Remove leading zeros to check MSB of significant byte
    bin_trimmed = drop_leading_zeros(bin)

    # If MSB is 1 (>= 0x80), we must prepend 0x00 to make it positive in two's complement
    case bin_trimmed do
      <<b, _::binary>> when b >= 0x80 ->
        content = <<0>> <> bin_trimmed
        <<0x02, byte_size(content)>> <> content

      _ ->
        content = if bin_trimmed == <<>>, do: <<0>>, else: bin_trimmed
        <<0x02, byte_size(content)>> <> content
    end
  end

  defp drop_leading_zeros(<<0, rest::binary>>), do: drop_leading_zeros(rest)
  defp drop_leading_zeros(bin), do: bin

  defp fix_coordinate_size(binary, size) do
    len = byte_size(binary)

    cond do
      len == size -> binary
      len < size -> <<0::size((size - len) * 8)>> <> binary
      len > size -> binary_part(binary, len - size, size)
    end
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
    <<_rp_id_hash::binary-size(32), _flags::8, sign_count::32-big, _rest::binary>> =
      authenticator_data

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
      last_used_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
  end

  @doc """
  Store a verified credential in the database.
  """
  def store_credential(credential_data, name \\ nil) do
    attrs =
      Map.merge(credential_data, %{
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

  # ============================================================================
  # DEVICE PAIRING
  # Functions to enable adding new devices via pairing tokens
  # ============================================================================

  alias Friends.Social.DevicePairing

  @doc """
  Create a new pairing token for a user.
  Token expires in 5 minutes and can only be used once.
  """
  def create_pairing_token(user_id) do
    token = DevicePairing.generate_token()
    expires_at = DevicePairing.default_expiry()

    %DevicePairing{}
    |> DevicePairing.changeset(%{
      user_id: user_id,
      token: token,
      expires_at: expires_at
    })
    |> Repo.insert()
  end

  @doc """
  Verify a pairing token is valid (exists, not expired, not claimed).
  Returns {:ok, pairing} or {:error, reason}
  """
  def verify_pairing_token(token) do
    token = String.upcase(String.trim(token))
    now = DateTime.utc_now()

    case Repo.get_by(DevicePairing, token: token) do
      nil ->
        {:error, :invalid_token}

      %{claimed: true} ->
        {:error, :already_claimed}

      %{expires_at: expires_at} = pairing ->
        if DateTime.compare(expires_at, now) == :gt do
          {:ok, Repo.preload(pairing, :user)}
        else
          {:error, :expired}
        end
    end
  end

  @doc """
  Claim a pairing token and register a new credential for the user.
  Returns {:ok, credential} or {:error, reason}
  """
  def claim_pairing_token(token, credential_data, device_name \\ nil) do
    case verify_pairing_token(token) do
      {:ok, pairing} ->
        # Mark token as claimed
        pairing
        |> Ecto.Changeset.change(%{claimed: true, device_name: device_name})
        |> Repo.update!()

        # Store the new credential
        credential_attrs = Map.put(credential_data, :user_id, pairing.user_id)
        store_credential(credential_attrs, device_name || "Paired Device")

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get a pairing token's details (for display).
  """
  def get_pairing_token(token) do
    token = String.upcase(String.trim(token))
    Repo.get_by(DevicePairing, token: token)
    |> case do
      nil -> nil
      pairing -> Repo.preload(pairing, :user)
    end
  end

  @doc """
  List active (unclaimed, non-expired) pairing tokens for a user.
  """
  def list_active_pairings(user_id) do
    now = DateTime.utc_now()

    from(p in DevicePairing,
      where: p.user_id == ^user_id and p.claimed == false and p.expires_at > ^now,
      order_by: [desc: p.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Clean up expired pairing tokens.
  """
  def cleanup_expired_pairings do
    now = DateTime.utc_now()

    from(p in DevicePairing, where: p.expires_at < ^now)
    |> Repo.delete_all()
  end
end
