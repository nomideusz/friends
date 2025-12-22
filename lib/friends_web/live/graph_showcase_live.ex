defmodule FriendsWeb.GraphShowcaseLive do
  @moduledoc """
  Temporary page to showcase all graph components for review.
  DELETE THIS FILE after deciding which graphs to keep.
  """
  use FriendsWeb, :live_view
  alias Friends.Social
  alias Friends.Repo
  import Ecto.Query

  @impl true
  def mount(_params, session, socket) do
    user_id = session["user_id"]
    user = if user_id, do: Social.get_user(user_id)

    graph_data = build_graph_data()
    chord_data = build_chord_data()
    constellation_data = build_constellation_data(user)

    {:ok,
     socket
     |> assign(:current_user, user)
     |> assign(:page_title, "Graph Showcase")
     |> assign(:graph_data, graph_data)
     |> assign(:chord_data, chord_data)
     |> assign(:constellation_data, constellation_data)}
  end

  # Build sample graph data for FriendGraph visualization
  # FriendGraph expects: nodes with {id, username, display_name, type, connected_at}
  # and edges with {from, to, type, connected_at}
  defp build_graph_data do
    users = Repo.all(from u in Friends.Social.User, limit: 50, select: u)
    
    friendships = Repo.all(
      from f in Friends.Social.Friendship,
        where: f.status == "accepted",
        limit: 100,
        select: %{user_id: f.user_id, friend_user_id: f.friend_user_id, inserted_at: f.inserted_at}
    )

    # First user is "self" for demo purposes
    {self_user, other_users} = case users do
      [first | rest] -> {first, rest}
      [] -> {nil, []}
    end

    nodes = 
      (if self_user do
        [%{
          id: self_user.id,
          username: self_user.username,
          display_name: self_user.display_name,
          type: "self",
          connected_at: NaiveDateTime.to_iso8601(self_user.inserted_at)
        }]
      else
        []
      end) ++
      Enum.map(other_users, fn user ->
        %{
          id: user.id,
          username: user.username,
          display_name: user.display_name,
          type: "friend",
          connected_at: NaiveDateTime.to_iso8601(user.inserted_at)
        }
      end)

    edges = 
      friendships
      |> Enum.map(fn f ->
        if f.user_id < f.friend_user_id do
          %{from: f.user_id, to: f.friend_user_id, type: "friend", connected_at: NaiveDateTime.to_iso8601(f.inserted_at)}
        else
          %{from: f.friend_user_id, to: f.user_id, type: "friend", connected_at: NaiveDateTime.to_iso8601(f.inserted_at)}
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

  # Build chord diagram data
  # ChordDiagram expects: nodes with {id, name, color, group} and matrix (adjacency matrix)
  defp build_chord_data do
    users = Repo.all(from u in Friends.Social.User, limit: 12, select: u)
    
    friendships = Repo.all(
      from f in Friends.Social.Friendship,
        where: f.status == "accepted",
        limit: 50,
        select: %{user_id: f.user_id, friend_user_id: f.friend_user_id}
    )

    # Build user index map for matrix
    user_list = Enum.with_index(users)
    user_id_to_index = Map.new(user_list, fn {u, i} -> {u.id, i} end)

    # Build adjacency matrix
    n = length(users)
    matrix = 
      if n > 0 do
        # Initialize empty matrix
        empty_matrix = for _ <- 1..n, do: for(_ <- 1..n, do: 0)
        
        # Fill in connections
        Enum.reduce(friendships, empty_matrix, fn f, acc ->
          i = Map.get(user_id_to_index, f.user_id)
          j = Map.get(user_id_to_index, f.friend_user_id)
          
          if i && j do
            acc
            |> List.update_at(i, fn row -> List.update_at(row, j, fn _ -> 1 end) end)
            |> List.update_at(j, fn row -> List.update_at(row, i, fn _ -> 1 end) end)
          else
            acc
          end
        end)
      else
        []
      end

    # Colors for nodes
    colors = ["#FF6B6B", "#4ECDC4", "#45B7D1", "#96CEB4", "#FFEAA7", "#DDA0DD", 
              "#98D8C8", "#F7DC6F", "#BB8FCE", "#85C1E9", "#F8B500", "#00CED1"]

    nodes = Enum.with_index(users) |> Enum.map(fn {u, i} ->
      %{
        id: u.id,
        name: u.display_name || u.username,
        color: Enum.at(colors, rem(i, length(colors))),
        group: if(i == 0, do: "self", else: "friend")
      }
    end)

    %{
      nodes: nodes,
      matrix: matrix
    }
  end

  defp build_constellation_data(current_user) do
    users = Repo.all(from u in Friends.Social.User, limit: 30, select: u)
    
    potentials = if current_user do
      users
      |> Enum.reject(fn u -> u.id == current_user.id end)
      |> Enum.take(15)
      |> Enum.map(fn u -> %{id: u.id, username: u.username, display_name: u.display_name} end)
    else
      []
    end

    %{
      center_user: if(current_user, do: %{id: current_user.id, username: current_user.username}, else: nil),
      potential_friends: potentials
    }
  end

  @impl true
  def handle_event("skip_welcome_graph", _params, socket), do: {:noreply, socket}
  def handle_event("skip_constellation", _params, socket), do: {:noreply, socket}
  def handle_event(_, _params, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-black text-white p-8">
      <div class="max-w-7xl mx-auto">
        <div class="mb-8 flex items-center justify-between">
          <div>
            <h1 class="text-3xl font-bold mb-2">Graph Component Showcase</h1>
            <p class="text-neutral-400">Review all graph components to decide which to keep</p>
          </div>
          <.link navigate={~p"/"} class="text-neutral-400 hover:text-white transition-colors">
            ← Back to Home
          </.link>
        </div>
        
        <div class="grid gap-8">
          <%!-- 1. WelcomeGraph --%>
          <section class="aether-card p-6">
            <div class="flex items-start justify-between mb-4">
              <div>
                <h2 class="text-xl font-bold text-white">1. WelcomeGraph</h2>
                <p class="text-neutral-400 text-sm">First-time user onboarding animation. D3 force layout showing network growth.</p>
                <p class="text-neutral-500 text-xs mt-1">File: <code>svelte/WelcomeGraph.svelte</code> (25KB)</p>
              </div>
              <span class="px-3 py-1 bg-green-500/20 text-green-400 text-sm rounded-full">Active</span>
            </div>
            <div class="bg-black/50 rounded-xl overflow-hidden h-[400px] relative">
              <div
                id="welcome-graph-demo"
                phx-hook="WelcomeGraph"
                phx-update="ignore"
                data-graph-data={Jason.encode!(@graph_data)}
                data-is-new-user="false"
                data-hide-controls="true"
                data-always-show="true"
                data-current-user-id={if @current_user, do: @current_user.id, else: ""}
                class="w-full h-full"
              ></div>
            </div>
          </section>

          <%!-- 2. FriendGraph --%>
          <section class="aether-card p-6">
            <div class="flex items-start justify-between mb-4">
              <div>
                <h2 class="text-xl font-bold text-white">2. FriendGraph</h2>
                <p class="text-neutral-400 text-sm">Personal friend network view. Shows user's direct connections.</p>
                <p class="text-neutral-500 text-xs mt-1">File: <code>svelte/FriendGraph.svelte</code> (20KB)</p>
              </div>
              <span class="px-3 py-1 bg-green-500/20 text-green-400 text-sm rounded-full">Active</span>
            </div>
            <div class="bg-black/50 rounded-xl overflow-hidden h-[400px] relative">
              <div
                id="friend-graph-demo"
                phx-hook="FriendGraph"
                phx-update="ignore"
                data-graph={Jason.encode!(@graph_data)}
                class="w-full h-full"
              ></div>
            </div>
          </section>


          <%!-- 3. ChordDiagram --%>
          <section class="aether-card p-6">
            <div class="flex items-start justify-between mb-4">
              <div>
                <h2 class="text-xl font-bold text-white">3. ChordDiagram</h2>
                <p class="text-neutral-400 text-sm">Circular chord diagram showing connection density between users.</p>
                <p class="text-neutral-500 text-xs mt-1">File: <code>svelte/ChordDiagram.svelte</code> (13KB)</p>
              </div>
              <span class="px-3 py-1 bg-yellow-500/20 text-yellow-400 text-sm rounded-full">Evaluate</span>
            </div>
            <div class="bg-black/50 rounded-xl overflow-hidden h-[400px] relative">
              <div
                id="chord-diagram-demo"
                phx-hook="ChordDiagram"
                phx-update="ignore"
                data-chord={Jason.encode!(@chord_data)}
                class="w-full h-full"
              ></div>
            </div>
          </section>


        </div>

        <%!-- Summary --%>
        <div class="mt-12 aether-card p-6">
          <h2 class="text-xl font-bold mb-4">Summary</h2>
          <table class="w-full text-sm">
            <thead>
              <tr class="text-left text-neutral-400 border-b border-white/10">
                <th class="pb-3">Component</th>
                <th class="pb-3">Size</th>
                <th class="pb-3">Purpose</th>
                <th class="pb-3">Status</th>
              </tr>
            </thead>
            <tbody class="text-neutral-300">
              <tr class="border-b border-white/5">
                <td class="py-3">WelcomeGraph</td>
                <td>25KB</td>
                <td>Onboarding/global visualization</td>
                <td class="text-green-400">Active</td>
              </tr>
              <tr class="border-b border-white/5">
                <td class="py-3">FriendGraph</td>
                <td>20KB</td>
                <td>Personal network (timeline hidden)</td>
                <td class="text-green-400">Active</td>
              </tr>
              <tr>
                <td class="py-3">ChordDiagram</td>
                <td>13KB</td>
                <td>Connection density</td>
                <td class="text-yellow-400">Evaluate</td>
              </tr>
            </tbody>
          </table>
          <p class="mt-4 text-neutral-500 text-sm">
            Total: ~58KB of Svelte component code (saved ~40KB by removing GlobalGraph, FriendsMap, ConstellationGraph)
          </p>
        </div>
      </div>
    </div>
    """
  end
end
