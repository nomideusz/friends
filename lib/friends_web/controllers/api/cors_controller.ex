defmodule FriendsWeb.API.CorsController do
  @moduledoc """
  Controller to handle CORS preflight OPTIONS requests.
  """
  use FriendsWeb, :controller

  def preflight(conn, _params) do
    origin = get_req_header(conn, "origin") |> List.first() || "*"

    conn
    |> put_resp_header("access-control-allow-origin", origin)
    |> put_resp_header("access-control-allow-methods", "GET, POST, PUT, DELETE, OPTIONS")
    |> put_resp_header("access-control-allow-headers", "authorization, content-type, x-requested-with")
    |> put_resp_header("access-control-allow-credentials", "true")
    |> put_resp_header("access-control-max-age", "86400")
    |> send_resp(204, "")
  end
end
