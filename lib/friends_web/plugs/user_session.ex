defmodule FriendsWeb.Plugs.UserSession do
  @moduledoc """
  Plug that reads the user_id from a cookie and sets it in the session
  for fast initial render in LiveView.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, :user_id) do
      nil ->
        # Try to get from cookie
        case conn.cookies["friends_user_id"] do
          nil -> conn
          user_id_str ->
            case Integer.parse(user_id_str) do
              {user_id, ""} -> put_session(conn, :user_id, user_id)
              _ -> conn
            end
        end
      _ ->
        # Already in session
        conn
    end
  end
end
