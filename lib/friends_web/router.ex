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
  end

  scope "/", FriendsWeb do
    pipe_through :browser

    get "/r/public-square", RedirectController, :public_square

    # Auth pages - no shared header needed
    live_session :auth, layout: {FriendsWeb.Layouts, :auth} do
      live "/login", LoginLive, :index
      live "/register", RegisterLive, :index
      live "/recover", RecoverLive, :index
      live "/link", LinkDeviceLive, :index
    end

    # App pages - shared header with user auth
    live_session :app,
      on_mount: [{FriendsWeb.Live.Hooks.UserAuth, :default}],
      layout: {FriendsWeb.Layouts, :app} do
      live "/", HomeLive, :index
      live "/devices", DevicesLive, :index
      live "/network", NetworkLive, :index
      live "/graph", GraphLive, :index
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
