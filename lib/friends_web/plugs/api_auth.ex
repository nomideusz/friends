defmodule FriendsWeb.Plugs.APIAuth do
  @moduledoc """
  Authentication plug for API endpoints.
  Checks for Bearer token or session-based authentication.
  """
  import Plug.Conn

  alias Friends.Social

  def init(opts), do: opts

  def call(conn, _opts) do
    with {:ok, user} <- get_user_from_auth(conn) do
      assign(conn, :current_user, user)
    else
      _ ->
        # Check session-based auth as fallback
        case get_session(conn, :user_id) do
          nil -> assign(conn, :current_user, nil)
          user_id -> assign(conn, :current_user, Social.get_user(user_id))
        end
    end
  end

  defp get_user_from_auth(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        # For now, treat token as user_id for simplicity
        # In production, this should verify a JWT or session token
        case Social.get_user(token) do
          nil -> {:error, :invalid_token}
          user -> {:ok, user}
        end

      _ ->
        {:error, :no_token}
    end
  end
end
