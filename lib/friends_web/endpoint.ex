defmodule FriendsWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :friends

  @session_options [
    store: :cookie,
    key: "_friends_key",
    signing_salt: "friends_salt",
    same_site: "Strict",
    http_only: true,
    secure: Mix.env() == :prod
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]

  # API socket for SvelteKit/mobile clients
  socket "/api/socket", FriendsWeb.UserSocket,
    websocket: true,
    longpoll: false

  plug Plug.Static,
    at: "/",
    from: :friends,
    gzip: false,
    only: FriendsWeb.static_paths()

  # plug Phoenix.Ecto.CheckRepoStatus, otp_app: :friends

  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug FriendsWeb.Router
end
