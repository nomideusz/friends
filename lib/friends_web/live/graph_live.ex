defmodule FriendsWeb.GraphLive do
  use FriendsWeb, :live_view
  alias Friends.Social
  alias Friends.Repo
  import Ecto.Query



  @impl true
  def mount(_params, session, socket) do
    user_id = session["user_id"]
    user = if user_id, do: Social.get_user(user_id)

    if connected?(socket) do
      # Subscribe to global friendship updates
      Phoenix.PubSub.subscribe(Friends.PubSub, "friends:global")
    end

    graph_data = build_global_graph_data()
    
    # Debug logging
    require Logger
    Logger.info("GraphLive: Loaded #{length(graph_data.nodes)} users, #{length(graph_data.edges)} edges")

    {:ok,
     socket
     |> assign(:current_user, user)
     |> assign(:page_title, "Global Network")
     |> assign(:graph_data, graph_data)
     |> assign(:show_user_dropdown, false)
     |> assign(:show_header_dropdown, false)
     |> assign(:current_route, "/graph")}
  end

  @impl true
  def handle_info({:friend_accepted, _}, socket) do
    {:noreply, refresh_graph(socket)}
  end

  @impl true
  def handle_info({:friend_removed, _}, socket) do
    {:noreply, refresh_graph(socket)}
  end

  @impl true
  def handle_info(_, socket), do: {:noreply, socket}

  # Event handlers for shared header
  @impl true
  def handle_event("toggle_user_dropdown", _params, socket) do
    {:noreply, assign(socket, :show_user_dropdown, !socket.assigns.show_user_dropdown)}
  end

  @impl true
  def handle_event("close_user_dropdown", _params, socket) do
    {:noreply, assign(socket, :show_user_dropdown, false)}
  end

  @impl true
  def handle_event("sign_out", _params, socket) do
    {:noreply, socket |> push_event("sign_out", %{})}
  end

  defp refresh_graph(socket) do
    graph_data = build_global_graph_data()
    socket
    |> assign(:graph_data, graph_data)
    |> push_event("global-graph-updated", %{graph_data: graph_data})
  end

  # Build graph data for ALL users and ALL friendships
  defp build_global_graph_data do
    # Get all users
    users = Repo.all(from u in Friends.Social.User, select: u)

    # Get all accepted friendships
    friendships = Repo.all(
      from f in Friends.Social.Friendship,
        where: f.status == "accepted",
        select: %{user_id: f.user_id, friend_user_id: f.friend_user_id, accepted_at: f.accepted_at}
    )

    # Build nodes
    nodes = Enum.map(users, fn user ->
      %{
        id: user.id,
        username: user.username,
        display_name: user.display_name,
        inserted_at: user.inserted_at
      }
    end)

    # Build edges (deduplicated - only include one direction)
    edges = 
      friendships
      |> Enum.map(fn f ->
        # Normalize to avoid duplicates (smaller ID first)
        if f.user_id < f.friend_user_id do
          %{from: f.user_id, to: f.friend_user_id, connected_at: f.accepted_at}
        else
          %{from: f.friend_user_id, to: f.user_id, connected_at: f.accepted_at}
        end
      end)
      |> Enum.uniq_by(fn e -> {e.from, e.to} end)

    %{
      nodes: nodes,
      edges: edges,
      stats: %{
        total_users: length(users),
        total_connections: length(edges)
      }
    }
  end



  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen text-white relative">
      <div class="opal-bg"></div>
      
      <div class="absolute inset-0 z-10 flex flex-col">
        <%!-- Header --%>
        <div class="flex items-center justify-between p-4 bg-black/30 backdrop-blur-sm border-b border-white/5">
          <div class="flex items-center gap-4">
            <.link navigate={~p"/?action=contacts"} class="text-neutral-400 hover:text-white transition-colors">
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-6 h-6">
                <path stroke-linecap="round" stroke-linejoin="round" d="M10.5 19.5L3 12m0 0l7.5-7.5M3 12h18" />
              </svg>
            </.link>
            <h1 class="text-xl font-bold">Global Network</h1>
          </div>
          
          <div class="flex items-center gap-4 text-sm text-neutral-400">
            <div class="flex items-center gap-2">
              <div class="w-2 h-2 rounded-full bg-blue-500 animate-pulse"></div>
              <span><span class="text-white font-semibold"><%= @graph_data.stats.total_users %></span> users</span>
            </div>
            <div class="w-px h-4 bg-white/10"></div>
            <div>
              <span class="text-white font-semibold"><%= @graph_data.stats.total_connections %></span> connections
            </div>
          </div>
        </div>
        
        <%!-- Graph Container --%>
        <div class="flex-1 relative">
          <%= if @graph_data do %>
            <div
              id="global-graph"
              phx-hook="GlobalGraph"
              phx-update="ignore"
              data-graph={Jason.encode!(@graph_data)}
              data-current-user-id={if @current_user, do: @current_user.id, else: ""}
              class="w-full h-full block"
            ></div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
