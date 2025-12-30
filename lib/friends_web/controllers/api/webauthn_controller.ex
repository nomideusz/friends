defmodule FriendsWeb.API.WebAuthnController do
  @moduledoc """
  JSON API controller for WebAuthn authentication.
  Provides endpoints for registration and login via FIDO2/WebAuthn.
  """
  use FriendsWeb, :controller

  alias Friends.{WebAuthn, Social}
  require Logger

  @doc """
  POST /api/v1/auth/register/challenge
  Generate registration challenge for a new or existing user.
  Creates the user if they don't exist.
  """
  def registration_challenge(conn, %{"username" => username}) do
    username = String.trim(username)

    # Get or create user
    user =
      case Social.get_user_by_username(username) do
        nil ->
          # Auto-create user for new registrations
          case Social.create_user(%{username: username, display_name: username}) do
            {:ok, user} -> user
            {:error, _} -> nil
          end

        existing_user ->
          existing_user
      end

    case user do
      nil ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to create user"})

      user ->
        # Generate challenge
        options = WebAuthn.generate_registration_challenge(user)

        # Store challenge and user_id in session for verification
        conn
        |> put_session(:webauthn_challenge, options.challenge)
        |> put_session(:webauthn_user_id, user.id)
        |> json(options)
    end
  end

  def registration_challenge(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Username required"})
  end

  @doc """
  POST /api/v1/auth/register
  Verify registration response and store credential.
  """
  def register(conn, %{"credential" => credential}) do
    challenge = get_session(conn, :webauthn_challenge)
    user_id = get_session(conn, :webauthn_user_id)

    cond do
      is_nil(challenge) ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "No pending registration challenge"})

      is_nil(user_id) ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "No user in session"})

      true ->
        # Verify the registration
        case WebAuthn.verify_registration(credential["response"], challenge, user_id) do
          {:ok, credential_data} ->
            # Store the credential
            case WebAuthn.store_credential(credential_data) do
              {:ok, _stored} ->
                user = Social.get_user(user_id)

                # Set authenticated session
                conn
                |> delete_session(:webauthn_challenge)
                |> delete_session(:webauthn_user_id)
                |> put_session(:user_id, user_id)
                |> json(%{
                  success: true,
                  user: %{
                    id: user.id,
                    username: user.username,
                    display_name: user.display_name,
                    avatar_url: user.avatar_url
                  }
                })

              {:error, reason} ->
                Logger.error("[WebAuthn API] Failed to store credential: #{inspect(reason)}")

                conn
                |> put_status(:internal_server_error)
                |> json(%{error: "Failed to store credential"})
            end

          {:error, reason} ->
            Logger.error("[WebAuthn API] Registration verification failed: #{inspect(reason)}")

            conn
            |> put_status(:unauthorized)
            |> json(%{error: "Registration verification failed"})
        end
    end
  end

  def register(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Credential required"})
  end

  @doc """
  POST /api/v1/auth/login/challenge
  Generate authentication challenge for an existing user.
  """
  def authentication_challenge(conn, %{"username" => username}) do
    username = String.trim(username)

    case Social.get_user_by_username(username) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "User not found"})

      user ->
        # Check if user has any credentials
        if WebAuthn.has_credentials?(user.id) do
          options = WebAuthn.generate_authentication_challenge(user)

          conn
          |> put_session(:webauthn_challenge, options.challenge)
          |> put_session(:webauthn_user_id, user.id)
          |> json(options)
        else
          conn
          |> put_status(:not_found)
          |> json(%{error: "No credentials registered for this user"})
        end
    end
  end

  def authentication_challenge(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Username required"})
  end

  @doc """
  POST /api/v1/auth/login
  Verify authentication response and create session.
  """
  def login(conn, %{"credential" => credential}) do
    challenge = get_session(conn, :webauthn_challenge)
    user_id = get_session(conn, :webauthn_user_id)

    cond do
      is_nil(challenge) ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "No pending authentication challenge"})

      is_nil(user_id) ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "No user in session"})

      true ->
        case WebAuthn.verify_authentication(credential["response"], challenge, user_id) do
          {:ok, _credential} ->
            user = Social.get_user(user_id)

            conn
            |> delete_session(:webauthn_challenge)
            |> delete_session(:webauthn_user_id)
            |> put_session(:user_id, user_id)
            |> json(%{
              success: true,
              user: %{
                id: user.id,
                username: user.username,
                display_name: user.display_name,
                avatar_url: user.avatar_url
              }
            })

          {:error, reason} ->
            Logger.error("[WebAuthn API] Authentication failed: #{inspect(reason)}")

            conn
            |> put_status(:unauthorized)
            |> json(%{error: "Authentication failed"})
        end
    end
  end

  def login(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Credential required"})
  end

  @doc """
  POST /api/v1/auth/logout
  Clear the user session.
  """
  def logout(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> json(%{success: true})
  end
end
