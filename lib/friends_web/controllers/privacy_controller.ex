defmodule FriendsWeb.PrivacyController do
  use FriendsWeb, :controller

  def index(conn, _params) do
    render(conn, :index)
  end
end
