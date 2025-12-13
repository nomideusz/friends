defmodule FriendsWeb.Plugs.UserSession do
  @moduledoc """
  Plug that reads the user_id from a cookie and sets it in the session
  for fast initial render in LiveView.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    cookie_user_id = parse_user_id_cookie(conn.cookies["friends_user_id"])
    session_user_id = get_session(conn, :user_id)

    cond do
      # Cookie is cleared but session has user_id -> user signed out, clear session
      is_nil(cookie_user_id) and not is_nil(session_user_id) ->
        delete_session(conn, :user_id)

      # Cookie has user_id, sync to session
      not is_nil(cookie_user_id) ->
        put_session(conn, :user_id, cookie_user_id)

      # Neither has user_id
      true ->
        conn
    end
  end

  defp parse_user_id_cookie(nil), do: nil
  defp parse_user_id_cookie(""), do: nil

  defp parse_user_id_cookie(user_id_str) do
    case Integer.parse(user_id_str) do
      {user_id, ""} -> user_id
      _ -> nil
    end
  end
end
