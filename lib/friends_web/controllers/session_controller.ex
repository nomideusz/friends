defmodule FriendsWeb.SessionController do
  @moduledoc """
  Controller for session management (logout via browser redirect).
  """
  use FriendsWeb, :controller

  def logout(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> redirect(to: "/auth")
  end
end
