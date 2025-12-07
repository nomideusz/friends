defmodule Friends.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      FriendsWeb.Telemetry,
      Friends.Repo,
      {DNSCluster, query: Application.get_env(:friends, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Friends.PubSub},
      Friends.Social.Presence,
      FriendsWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Friends.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    FriendsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

