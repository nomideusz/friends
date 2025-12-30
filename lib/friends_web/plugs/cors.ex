defmodule FriendsWeb.Plugs.Cors do
  @moduledoc """
  CORS plug for API endpoints.
  Allows SvelteKit dev server and Capacitor origins.
  """
  import Plug.Conn

  @allowed_origins [
    "http://localhost:5173",      # SvelteKit dev
    "http://localhost:4173",      # SvelteKit preview
    "capacitor://localhost",      # Capacitor iOS
    "http://localhost"            # Capacitor Android
  ]

  def init(opts), do: opts

  def call(conn, _opts) do
    origin = get_req_header(conn, "origin") |> List.first()

    if origin && allowed_origin?(origin) do
      conn
      |> put_resp_header("access-control-allow-origin", origin)
      |> put_resp_header("access-control-allow-methods", "GET, POST, PUT, DELETE, OPTIONS")
      |> put_resp_header("access-control-allow-headers", "authorization, content-type, x-requested-with")
      |> put_resp_header("access-control-allow-credentials", "true")
      |> put_resp_header("access-control-max-age", "86400")
      |> handle_preflight()
    else
      conn
    end
  end

  defp allowed_origin?(origin) do
    origin in @allowed_origins ||
      String.starts_with?(origin, "http://localhost:") ||
      String.starts_with?(origin, "https://localhost:")
  end

  defp handle_preflight(%{method: "OPTIONS"} = conn) do
    conn
    |> send_resp(204, "")
    |> halt()
  end

  defp handle_preflight(conn), do: conn
end
