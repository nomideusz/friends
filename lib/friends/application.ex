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
      # Cache for graph data and other performance optimizations
      {Cachex, name: :graph_cache},
      FriendsWeb.Endpoint
    ] ++ fcm_children()

    opts = [strategy: :one_for_one, name: Friends.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp fcm_children do
    case Application.get_env(:friends, :fcm_service_account) do
      nil ->
        []
      creds ->
        [
          {Goth, name: Friends.FCM.Goth, source: {:service_account, creds}},
          {Friends.FCM, [
             adapter: Pigeon.FCM,
             auth: Friends.FCM.Goth,
             project_id: creds["project_id"]
           ]}
        ]
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    FriendsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
