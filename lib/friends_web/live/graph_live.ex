defmodule FriendsWeb.GraphLive do
  use FriendsWeb, :live_view
  alias Friends.Social
  alias Friends.Repo
  import Ecto.Query

  @colors ~w(#ef4444 #f97316 #eab308 #22c55e #14b8a6 #3b82f6 #8b5cf6 #ec4899)

  @impl true
  def mount(_params, session, socket) do
    user_id = session["user_id"]

    if user_id do
      user = Social.get_user(user_id)

      if user do
        # Get all relationship types for a richer graph
        graph_data = build_graph_data(user)

        {:ok,
         socket
         |> assign(:current_user, user)
         |> assign(:graph_data, graph_data)
         |> assign(:page_title, "Friend Graph")}
      else
        {:ok,
         socket
         |> put_flash(:error, "User not found")
         |> redirect(to: "/")}
      end
    else
      {:ok,
       socket
       |> put_flash(:error, "You must be logged in to view your friend graph")
       |> redirect(to: "/")}
    end
  end

  defp build_graph_data(user) do
    user_id = user.id

    # 1. People I trust (confirmed)
    my_trusted = Social.list_trusted_friends(user_id)

    # 2. People who trust me (confirmed) - reverse relationships
    people_who_trust_me =
      Repo.all(
        from tf in Friends.Social.TrustedFriend,
          where: tf.trusted_user_id == ^user_id and tf.status == "confirmed",
          preload: [:user]
      )

    # 3. Pending outgoing requests (I sent)
    pending_outgoing = Social.list_sent_trust_requests(user_id)

    # 4. Pending incoming requests (they sent to me)
    pending_incoming = Social.list_pending_trust_requests(user_id)

    # 5. People I invited (via invite codes)
    invitees =
      Repo.all(
        from u in Friends.Social.User,
          where: u.invited_by_id == ^user_id and u.id != ^user_id
      )

    # 6. Person who invited me
    inviter =
      if user.invited_by_id do
        Social.get_user(user.invited_by_id)
      else
        nil
      end

    # Build nodes map to avoid duplicates
    nodes_map = %{}

    # Add current user as central node
    current_user_node = %{
      id: user.id,
      username: user.username,
      display_name: user.display_name,
      color: user_color(user.id),
      type: "self"
    }

    nodes_map = Map.put(nodes_map, user.id, current_user_node)

    # Add all related users
    nodes_map =
      Enum.reduce(my_trusted, nodes_map, fn tf, acc ->
        Map.put_new(acc, tf.trusted_user.id, %{
          id: tf.trusted_user.id,
          username: tf.trusted_user.username,
          display_name: tf.trusted_user.display_name,
          color: user_color(tf.trusted_user.id),
          type: "trusted"
        })
      end)

    nodes_map =
      Enum.reduce(people_who_trust_me, nodes_map, fn tf, acc ->
        Map.put_new(acc, tf.user.id, %{
          id: tf.user.id,
          username: tf.user.username,
          display_name: tf.user.display_name,
          color: user_color(tf.user.id),
          type: "trusts_me"
        })
      end)

    nodes_map =
      Enum.reduce(pending_outgoing, nodes_map, fn tf, acc ->
        Map.put_new(acc, tf.trusted_user.id, %{
          id: tf.trusted_user.id,
          username: tf.trusted_user.username,
          display_name: tf.trusted_user.display_name,
          color: user_color(tf.trusted_user.id),
          type: "pending_outgoing"
        })
      end)

    nodes_map =
      Enum.reduce(pending_incoming, nodes_map, fn tf, acc ->
        Map.put_new(acc, tf.user.id, %{
          id: tf.user.id,
          username: tf.user.username,
          display_name: tf.user.display_name,
          color: user_color(tf.user.id),
          type: "pending_incoming"
        })
      end)

    nodes_map =
      Enum.reduce(invitees, nodes_map, fn u, acc ->
        Map.put_new(acc, u.id, %{
          id: u.id,
          username: u.username,
          display_name: u.display_name,
          color: user_color(u.id),
          type: "invitee"
        })
      end)

    nodes_map =
      if inviter do
        Map.put_new(nodes_map, inviter.id, %{
          id: inviter.id,
          username: inviter.username,
          display_name: inviter.display_name,
          color: user_color(inviter.id),
          type: "inviter"
        })
      else
        nodes_map
      end

    # Build edges with types
    edges = []

    # Edges for people I trust
    edges =
      Enum.reduce(my_trusted, edges, fn tf, acc ->
        [%{from: user.id, to: tf.trusted_user.id, type: "trusted"} | acc]
      end)

    # Edges for people who trust me (only if not already connected)
    edges =
      Enum.reduce(people_who_trust_me, edges, fn tf, acc ->
        # Check if reverse edge already exists
        has_reverse = Enum.any?(my_trusted, fn t -> t.trusted_user.id == tf.user.id end)

        if has_reverse do
          # Update existing edge to be bidirectional (handled in JS)
          acc
        else
          [%{from: tf.user.id, to: user.id, type: "trusts_me"} | acc]
        end
      end)

    # Edges for pending outgoing
    edges =
      Enum.reduce(pending_outgoing, edges, fn tf, acc ->
        [%{from: user.id, to: tf.trusted_user.id, type: "pending_outgoing"} | acc]
      end)

    # Edges for pending incoming
    edges =
      Enum.reduce(pending_incoming, edges, fn tf, acc ->
        [%{from: tf.user.id, to: user.id, type: "pending_incoming"} | acc]
      end)

    # Edges for invitees
    edges =
      Enum.reduce(invitees, edges, fn u, acc ->
        [%{from: user.id, to: u.id, type: "invited"} | acc]
      end)

    # Edge for inviter
    edges =
      if inviter do
        [%{from: inviter.id, to: user.id, type: "invited"} | edges]
      else
        edges
      end

    # Count different relationship types
    mutual_count =
      Enum.count(my_trusted, fn tf ->
        Enum.any?(people_who_trust_me, fn ptm -> ptm.user.id == tf.trusted_user.id end)
      end)

    %{
      current_user: current_user_node,
      nodes: Map.values(nodes_map),
      edges: edges,
      stats: %{
        total_connections: map_size(nodes_map) - 1,
        mutual_friends: mutual_count,
        i_trust: length(my_trusted),
        trust_me: length(people_who_trust_me),
        pending_out: length(pending_outgoing),
        pending_in: length(pending_incoming),
        invited: length(invitees)
      }
    }
  end

  @impl true
  def handle_event("node_clicked", %{"user_id" => user_id}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Clicked on user #{user_id}")}
  end

  defp user_color(user_id) do
    Enum.at(@colors, rem(user_id, length(@colors)))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen text-white relative">
      <%!-- Animated opalescent background --%>
      <div class="opal-bg"></div>

      <%!-- Header --%>
      <header class="sticky top-0 z-40 backdrop-blur-md bg-black/30 border-b border-white/10">
        <div class="max-w-7xl mx-auto px-4 py-4">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-4">
              <a href="/" class="text-white/60 hover:text-white transition-colors">
                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
                </svg>
              </a>
              <h1 class="text-xl font-medium">Friend Graph</h1>
            </div>
            <div class="text-sm text-white/60">
              <%= @graph_data.stats.total_connections %> connections
            </div>
          </div>
        </div>
      </header>

      <%!-- Main content --%>
      <main class="relative z-10">
        <div class="max-w-7xl mx-auto px-4 py-6">
          <%= if @graph_data.stats.total_connections > 0 do %>
            <div class="bg-black/30 backdrop-blur-sm border border-white/10 rounded-lg overflow-hidden">
              <div
                id="friend-graph"
                phx-hook="FriendGraph"
                phx-update="ignore"
                data-graph={Jason.encode!(@graph_data)}
                class="w-full"
                style="height: 70vh; min-height: 500px;"
              >
              </div>
            </div>

            <%!-- Stats & Legend --%>
            <div class="mt-6 grid grid-cols-2 md:grid-cols-4 gap-3">
              <%= if @graph_data.stats.mutual_friends > 0 do %>
                <div class="p-3 bg-black/30 backdrop-blur-sm border border-white/10 rounded-lg">
                  <div class="text-2xl font-bold text-green-400"><%= @graph_data.stats.mutual_friends %></div>
                  <div class="text-xs text-white/60">mutual friends</div>
                </div>
              <% end %>
              <%= if @graph_data.stats.i_trust > 0 do %>
                <div class="p-3 bg-black/30 backdrop-blur-sm border border-white/10 rounded-lg">
                  <div class="text-2xl font-bold text-blue-400"><%= @graph_data.stats.i_trust %></div>
                  <div class="text-xs text-white/60">I trust</div>
                </div>
              <% end %>
              <%= if @graph_data.stats.trust_me > 0 do %>
                <div class="p-3 bg-black/30 backdrop-blur-sm border border-white/10 rounded-lg">
                  <div class="text-2xl font-bold text-purple-400"><%= @graph_data.stats.trust_me %></div>
                  <div class="text-xs text-white/60">trust me</div>
                </div>
              <% end %>
              <%= if @graph_data.stats.pending_in > 0 do %>
                <div class="p-3 bg-black/30 backdrop-blur-sm border border-white/10 rounded-lg">
                  <div class="text-2xl font-bold text-yellow-400"><%= @graph_data.stats.pending_in %></div>
                  <div class="text-xs text-white/60">pending requests</div>
                </div>
              <% end %>
              <%= if @graph_data.stats.invited > 0 do %>
                <div class="p-3 bg-black/30 backdrop-blur-sm border border-white/10 rounded-lg">
                  <div class="text-2xl font-bold text-pink-400"><%= @graph_data.stats.invited %></div>
                  <div class="text-xs text-white/60">invited</div>
                </div>
              <% end %>
            </div>

            <%!-- Legend --%>
            <div class="mt-4 p-4 bg-black/30 backdrop-blur-sm border border-white/10 rounded-lg">
              <h3 class="text-sm font-medium text-white/80 mb-3">Legend</h3>
              <div class="flex flex-wrap gap-4 text-xs text-white/60">
                <div class="flex items-center gap-2">
                  <div class="w-8 h-0.5 bg-white"></div>
                  <span>mutual trust</span>
                </div>
                <div class="flex items-center gap-2">
                  <div class="w-8 h-0.5 bg-blue-400"></div>
                  <span>I trust</span>
                </div>
                <div class="flex items-center gap-2">
                  <div class="w-8 h-0.5 bg-purple-400"></div>
                  <span>trusts me</span>
                </div>
                <div class="flex items-center gap-2">
                  <div class="w-8 h-0.5 bg-yellow-400/50 border-dashed border-t"></div>
                  <span>pending</span>
                </div>
                <div class="flex items-center gap-2">
                  <div class="w-8 h-0.5 bg-pink-400/50"></div>
                  <span>invited</span>
                </div>
              </div>
            </div>
          <% else %>
            <div class="text-center py-20">
              <div class="text-6xl mb-4">👥</div>
              <h2 class="text-xl font-medium text-white/80 mb-2">No connections yet</h2>
              <p class="text-white/60 mb-6">
                Invite friends or send trust requests to see your social graph!
              </p>
              <a
                href="/"
                class="inline-flex items-center gap-2 px-4 py-2 bg-white text-black font-medium hover:bg-neutral-200 transition-colors"
              >
                Go back home
              </a>
            </div>
          <% end %>
        </div>
      </main>
    </div>
    """
  end
end
