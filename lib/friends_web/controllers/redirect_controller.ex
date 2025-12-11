defmodule FriendsWeb.RedirectController do
  use FriendsWeb, :controller

  def public_square(conn, _params) do
    conn
    |> Phoenix.Controller.redirect(to: ~p"/r/lobby")
  end
end

