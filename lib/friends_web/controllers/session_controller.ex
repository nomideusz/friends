defmodule FriendsWeb.SessionController do
  @moduledoc """
  Controller for session management (logout via browser redirect).
  """
  use FriendsWeb, :controller

  def logout(conn, _params) do
    conn
    |> delete_session(:user_id)
    |> clear_session()
    |> configure_session(drop: true, renew: true)
    |> redirect(to: "/secret-auth")
  end
end
