defmodule FriendsWeb.Router do
  use FriendsWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FriendsWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug FriendsWeb.Plugs.UserSession
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :fetch_session
    plug FriendsWeb.Plugs.Cors
    plug FriendsWeb.Plugs.APIAuth
  end

  # Handle CORS preflight requests
  scope "/api" do
    options "/*path", FriendsWeb.API.CorsController, :preflight
  end

  # JSON API for SvelteKit frontend
  scope "/api/v1", FriendsWeb.API do
    pipe_through :api

    # WebAuthn auth (no auth required for these)
    post "/auth/register/challenge", WebAuthnController, :registration_challenge
    post "/auth/register", WebAuthnController, :register
    post "/auth/login/challenge", WebAuthnController, :authentication_challenge
    post "/auth/login", WebAuthnController, :login
    post "/auth/logout", WebAuthnController, :logout

    get "/me", UserController, :me
    get "/users/search", UserController, :search
    get "/users/:id", UserController, :show
    get "/friends", UserController, :friends

    get "/rooms", RoomController, :index
    get "/rooms/:id", RoomController, :show
    get "/rooms/:id/messages", RoomController, :messages

    get "/graph", GraphController, :index
  end

  scope "/", FriendsWeb do
    pipe_through :browser

    get "/r/public-square", RedirectController, :public_square
    
    # Redirects from old auth URLs to unified /auth
    get "/login", RedirectController, :auth
    get "/register", RedirectController, :auth

    # Public countdown page
    live_session :countdown, layout: {FriendsWeb.Layouts, :auth} do
      live "/auth", CountdownLive, :index
    end

    # Browser logout (GET for redirects from LiveView)
    get "/auth/logout", SessionController, :logout

    # Secret auth routes for testing (hidden from public)
    live_session :secret_auth, layout: {FriendsWeb.Layouts, :auth} do
      live "/secret-auth", AuthLive, :index
      live "/recover", RecoverLive, :index
      live "/link", LinkDeviceLive, :index
      live "/pair", PairLive, :index
      live "/pair/:token", PairLive, :index
    end

    # App pages - shared header with user auth
    live_session :app,
      on_mount: [{FriendsWeb.Live.Hooks.UserAuth, :default}],
      layout: {FriendsWeb.Layouts, :app} do
      live "/", HomeLive, :index
      live "/devices", DevicesLive, :index

      live "/graph", GraphLive, :index
      live "/graph-showcase", GraphShowcaseLive, :index
      live "/r/:room", HomeLive, :room
    end
  end

  if Application.compile_env(:friends, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: FriendsWeb.Telemetry
    end
  end
end
