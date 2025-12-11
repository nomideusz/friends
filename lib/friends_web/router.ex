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

    live "/", HomeLive, :index
    live "/login", LoginLive, :index
    live "/register", RegisterLive, :index
    live "/recover", RecoverLive, :index
    live "/link", LinkDeviceLive, :index
    live "/devices", DevicesLive, :index
    live "/graph", GraphLive, :index
    live "/r/:room", HomeLive, :room
  end

  if Application.compile_env(:friends, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: FriendsWeb.Telemetry
    end
  end
end

