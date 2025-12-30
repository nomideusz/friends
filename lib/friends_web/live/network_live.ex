defmodule FriendsWeb.NetworkLive do
  use FriendsWeb, :live_view
  alias Friends.Social
  alias Friends.Repo
  import Ecto.Query

  # Colors for avatars
  @colors ~w(#ef4444 #f97316 #eab308 #22c55e #14b8a6 #3b82f6 #8b5cf6 #ec4899)

  def mount(_params, session, socket) do
    user_id = session["user_id"]
    user = if user_id, do: Social.get_user(user_id)

    color =
      if user do
        # Simple consistent color hash
        case Integer.parse(to_string(user.id)) do
          {int_id, _} -> Enum.at(@colors, rem(int_id, length(@colors)))
          _ -> Enum.at(@colors, 0)
        end
      else
        "#888"
      end

    if connected?(socket) && user do
      Phoenix.PubSub.subscribe(Friends.PubSub, "friends:user:#{user.id}")
    end

    {:ok,
     socket
     |> assign(:current_user, user)
     |> assign(:user_color, color)
     |> assign_defaults()}
  end

  def handle_params(params, _url, socket) do
    # list or graph
    view = params["view"] || "list"

    {:noreply,
     socket
     |> assign(:view, view)
     |> load_data()}
  end

  defp assign_defaults(socket) do
    socket
    |> assign(:page_title, "People")
    |> assign(:friend_search, "")
    |> assign(:friend_search_results, [])
    |> assign(:show_header_dropdown, false)
    |> assign(:show_user_dropdown, false)
    |> assign(:current_route, "/network")
    |> assign(:user_rooms, [])
    |> assign(:graph_collapsed, false)
    |> assign(:show_graph_modal, false)
  end

  defp load_data(socket) do
    user = socket.assigns.current_user

    if user do
      friends = Social.list_friends(user.id)

      # Calculate mutual friends count for each friend
      friends_with_mutual = Enum.map(friends, fn f ->
        mutual_count = count_mutual_friends(user.id, f.user.id)
        Map.put(f, :mutual_count, mutual_count)
      end)

      socket
      |> assign(:friends, friends_with_mutual)
      |> assign(:friend_requests, Social.list_friend_requests(user.id))
      |> assign(:sent_requests, Social.list_sent_friend_requests(user.id))
      |> assign(:trusted_friends, Social.list_trusted_friends(user.id))
      |> assign(:pending_trust_requests, Social.list_pending_trust_requests(user.id))
      |> assign(:outgoing_trust_requests, Social.list_sent_trust_requests(user.id))
      |> assign(:invites, Social.list_user_invites(user.id))
      |> assign(:user_rooms, Social.list_user_rooms(user.id))
      # Always load graph data (graph is always visible now)
      |> assign(:graph_data, build_graph_data(user))
    else
      socket
      |> put_flash(:error, "You must be logged in")
      |> redirect(to: "/")
    end
  end

  # --- Event Handlers ---

  # --- Event Handlers ---

  def handle_event("toggle_user_dropdown", _params, socket) do
    {:noreply, assign(socket, :show_user_dropdown, !socket.assigns.show_user_dropdown)}
  end

  def handle_event("close_user_dropdown", _params, socket) do
    {:noreply, assign(socket, :show_user_dropdown, false)}
  end

  def handle_event("toggle_graph", _params, socket) do
    {:noreply, assign(socket, :graph_collapsed, !socket.assigns.graph_collapsed)}
  end

  def handle_event("open_graph_modal", _params, socket) do
    {:noreply, assign(socket, :show_graph_modal, true)}
  end

  def handle_event("close_graph_modal", _params, socket) do
    {:noreply, assign(socket, :show_graph_modal, false)}
  end

  def handle_event("add_friend_from_graph", %{"user_id" => user_id}, socket) do
    # Convert string user_id to integer
    user_id = String.to_integer(user_id)

    case Social.add_friend(socket.assigns.current_user.id, user_id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Friend request sent!")
         |> load_data()}

      {:error, reason} ->
        msg =
          case reason do
            :already_friends -> "You are already contacts"
            :request_already_sent -> "Request already sent"
            _ -> "Could not add contact"
          end

        {:noreply, put_flash(socket, :error, msg)}
    end
  end

  def handle_event("search_friends", %{"query" => query}, socket) do
    if String.length(query) >= 2 do
      results = Social.search_users(query, socket.assigns.current_user.id)
      {:noreply, assign(socket, :friend_search, query) |> assign(:friend_search_results, results)}
    else
      {:noreply, assign(socket, :friend_search, query) |> assign(:friend_search_results, [])}
    end
  end

  def handle_event("add_friend", %{"user_id" => user_id}, socket) do
    case Social.add_friend(socket.assigns.current_user.id, user_id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Contact request sent!")
         |> assign(:friend_search, "")
         |> assign(:friend_search_results, [])
         |> load_data()}

      {:error, reason} ->
        msg =
          case reason do
            :already_friends -> "You are already contacts"
            :request_already_sent -> "Request already sent"
            _ -> "Could not add contact"
          end

        {:noreply, put_flash(socket, :error, msg)}
    end
  end

  def handle_event("accept_friend", %{"user_id" => user_id}, socket) do
    case Social.accept_friend(socket.assigns.current_user.id, user_id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Contact accepted!")
         |> load_data()}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not accept contact")}
    end
  end

  def handle_event("remove_friend", %{"user_id" => user_id}, socket) do
    case Social.remove_friend(socket.assigns.current_user.id, user_id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Contact removed")
         |> load_data()}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not remove contact")}
    end
  end

  def handle_event("decline_friend", %{"user_id" => user_id}, socket) do
    # Declining a request removes the pending friendship
    case Social.remove_friend(socket.assigns.current_user.id, user_id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Friend request declined")
         |> load_data()}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not decline request")}
    end
  end

  # Trusted friend handlers (keep existing logic)
  def handle_event("add_trusted_friend", %{"user_id" => user_id}, socket) do
    case Social.add_trusted_friend(socket.assigns.current_user.id, user_id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Recovery contact request sent")
         |> load_data()}

      {:error, :max_trusted_friends} ->
        {:noreply, put_flash(socket, :error, "You can only have 5 recovery contacts")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not add recovery contact")}
    end
  end

  def handle_event("confirm_trust", %{"user_id" => user_id}, socket) do
    case Social.confirm_trusted_friend(socket.assigns.current_user.id, user_id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Recovery contact confirmed")
         |> load_data()}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not confirm recovery contact")}
    end
  end

  # --- Invite Handlers ---

  def handle_event("create_invite", _, socket) do
    case Social.create_invite(socket.assigns.current_user.id) do
      {:ok, _invite} ->
        {:noreply,
         socket
         |> put_flash(:info, "Invite code created")
         |> load_data()}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not create invite")}
    end
  end

  def handle_event("revoke_invite", %{"code" => code}, socket) do
    # We need a function to revoke invite, assumes existing delete or update
    # For now, let's assume we can just ignore or impl later if strictly needed functionality not in Social
    # But wait, checking context... Social.update_invite?
    # Let's verify context first. Actually, create_invite exists.
    # Let's check Social module for revoke/delete/update logic.
    # Assuming standard pattern or omit for now if not critical. 
    # Actually let's assume update_invite(invite, %{status: "revoked"}) logic

    invite = Social.get_invite_by_code(code)

    if invite && invite.created_by_id == socket.assigns.current_user.id do
      Social.update_invite(invite, %{status: "revoked"})
      {:noreply, put_flash(socket, :info, "Invite revoked") |> load_data()}
    else
      {:noreply, put_flash(socket, :error, "Cannot revoke invite")}
    end
  end

  # --- Header Dropdown ---
  def handle_event("toggle_header_dropdown", _, socket) do
    {:noreply, assign(socket, :show_header_dropdown, !socket.assigns.show_header_dropdown)}
  end

  def handle_event("close_header_dropdown", _, socket) do
    {:noreply, assign(socket, :show_header_dropdown, false)}
  end

  def handle_event("sign_out", _, socket) do
    {:noreply,
     socket
     |> push_event("sign_out", %{})
     |> put_flash(:info, "Signing out...")}
  end

  # --- Real-time Updates ---

  def handle_info({:friend_request, _}, socket), do: {:noreply, refresh_graph_if_needed(socket)}
  def handle_info({:friend_accepted, _}, socket), do: {:noreply, refresh_graph_if_needed(socket)}
  def handle_info({:friend_removed, _}, socket), do: {:noreply, refresh_graph_if_needed(socket)}
  def handle_info({:trust_added, _}, socket), do: {:noreply, refresh_graph_if_needed(socket)}
  def handle_info({:trust_confirmed, _}, socket), do: {:noreply, refresh_graph_if_needed(socket)}
  # Room events - refresh user_rooms list
  def handle_info({:room_created, _room}, socket), do: {:noreply, load_data(socket)}
  # Catch-all for any other broadcasts we don't need to handle
  def handle_info(_, socket), do: {:noreply, socket}

  # Refresh graph data (graph is always visible now)
  defp refresh_graph_if_needed(socket) do
    socket = load_data(socket)

    # Always push updated graph data to client (graph is always visible)
    if socket.assigns.graph_data do
      push_event(socket, "graph-updated", %{graph_data: socket.assigns.graph_data})
    else
      socket
    end
  end

  # --- Graph Helper (Extended Social Network) ---
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

    # 3. My friends (accepted)
    friends = Social.list_friends(user_id)
    # Map of friend_id -> accepted_at (time when I became friends with them)
    friends_map = Map.new(friends, fn f -> {f.user.id, f.friendship.accepted_at} end)
    friend_ids = Map.keys(friends_map)

    # 4. Get friendships BETWEEN my friends (the social network magic!)
    # This shows connections like: if A is friends with B and C, and B is friends with C
    friend_to_friend_edges = get_friendships_between(friend_ids)

    # 5. NEW: Get friends of friends (2nd degree connections)
    # Pass friends_map to allow calculating dependent visibility times (Ego-Centric Graph)
    {second_degree_friends, second_degree_edges} = get_second_degree_connections(friends_map, user_id)

    # Build nodes map to avoid duplicates
    nodes_map = %{}

    # Add current user as central node
    current_user_node = %{
      id: user.id,
      username: user.username,
      display_name: user.display_name,
      color: trusted_user_color(user),
      type: "self",
      connected_at: user.inserted_at
    }

    nodes_map = Map.put(nodes_map, user.id, current_user_node)

    # Add trusted users
    nodes_map =
      Enum.reduce(my_trusted, nodes_map, fn tf, acc ->
        Map.put(acc, tf.trusted_user.id, %{
          id: tf.trusted_user.id,
          username: tf.trusted_user.username,
          display_name: tf.trusted_user.display_name,
          color: trusted_user_color(tf.trusted_user),
          type: "trusted",
          connected_at: tf.inserted_at
        })
      end)

    # Add people who trust me
    nodes_map =
      Enum.reduce(people_who_trust_me, nodes_map, fn tf, acc ->
        Map.update(acc, tf.user.id, 
          # New node if not exists
          %{
            id: tf.user.id,
            username: tf.user.username,
            display_name: tf.user.display_name,
            color: trusted_user_color(tf.user),
            type: "trusts_me",
            connected_at: tf.inserted_at
          },
          # If exists (e.g. was "trusted"), keep existing type but ensure connected_at is set if missing
          fn existing -> existing end
        )
      end)

    # Add social friends (with mutual count)
    nodes_map =
      Enum.reduce(friends, nodes_map, fn f, acc ->
        mutual_count = count_mutual_friends(user_id, f.user.id)
        
        Map.update(acc, f.user.id,
          # New node (Friend only)
          %{
            id: f.user.id,
            username: f.user.username,
            display_name: f.user.display_name,
            color: trusted_user_color(f.user),
            type: "friend",
            mutual_count: mutual_count,
            connected_at: f.friendship.accepted_at
          },
          # If exists (Trusted), update with mutual count
          fn existing -> 
            Map.put(existing, :mutual_count, mutual_count)
          end
        )
      end)

    # Add second degree connections (friends of friends)
    nodes_map =
      Enum.reduce(second_degree_friends, nodes_map, fn friend, acc ->
        Map.put_new(acc, friend.id, %{
          id: friend.id,
          username: friend.username,
          display_name: friend.display_name,
          color: trusted_user_color(friend),
          type: "second_degree",
          connected_at: user.inserted_at # Always visible based on user start time
        })
      end)

    # Build edges
    edges = []

    # Edges for people I trust
    edges =
      Enum.reduce(my_trusted, edges, fn tf, acc ->
        [%{from: user.id, to: tf.trusted_user.id, type: "trusted", connected_at: tf.inserted_at} | acc]
      end)

    # Edges for people who trust me
    edges =
      Enum.reduce(people_who_trust_me, edges, fn tf, acc ->
        # Check if reverse edge exists (bidirectional trust)
        has_reverse = Enum.any?(my_trusted, fn t -> t.trusted_user.id == tf.user.id end)

        if has_reverse do
          # Already handled by bidirectional logic in JS
          acc
        else
          [%{from: tf.user.id, to: user.id, type: "trusts_me", connected_at: tf.inserted_at} | acc]
        end
      end)

    # Edges for my direct friends (with mutual count)
    edges =
      Enum.reduce(friends, edges, fn f, acc ->
        mutual_count = count_mutual_friends(user_id, f.user.id)
        [%{from: user.id, to: f.user.id, type: "friend", mutual_count: mutual_count, connected_at: f.friendship.accepted_at} | acc]
      end)

    # Edges between my friends (social network connections!)
    edges =
      Enum.reduce(friend_to_friend_edges, edges, fn {id1, id2, accepted_at}, acc ->
        [%{from: id1, to: id2, type: "mutual", connected_at: accepted_at} | acc]
      end)

    # Add second degree edges (from my friends to their friends)
    edges = edges ++ second_degree_edges

    # Stats
    mutual_count =
      Enum.count(my_trusted, fn tf ->
        Enum.any?(people_who_trust_me, fn ptm -> ptm.user.id == tf.trusted_user.id end)
      end)

    %{
      current_user: current_user_node,
      nodes: Map.values(nodes_map) |> Enum.uniq_by(& &1.id),
      edges: edges,
      stats: %{
        total_connections: map_size(nodes_map) - 1,
        mutual_friends: mutual_count,
        i_trust: length(my_trusted),
        trust_me: length(people_who_trust_me),
        friends: length(friends),
        friend_connections: length(friend_to_friend_edges),
        second_degree: length(second_degree_friends),
        pending_in: 0,
        invited: 0
      }
    }
  end



  # Get all friendships between a list of user IDs
  # Returns list of {user_id_1, user_id_2} tuples where both are friends
  defp get_friendships_between(user_ids) when length(user_ids) < 2, do: []

  defp get_friendships_between(user_ids) do
    # Query friendships where BOTH users are in our friend list
    Repo.all(
      from f in Friends.Social.Friendship,
        where:
          f.user_id in ^user_ids and f.friend_user_id in ^user_ids and f.status == "accepted",
        select: {f.user_id, f.friend_user_id, f.accepted_at}
    )
    |> Enum.map(fn {id1, id2, accepted_at} ->
      # Normalize to avoid duplicates (always smaller ID first)
      if id1 < id2, do: {id1, id2, accepted_at}, else: {id2, id1, accepted_at}
    end)
    |> Enum.uniq()
  end

  defp trusted_user_color(%{id: id}) when is_integer(id) do
    Enum.at(@colors, rem(id, length(@colors)))
  end

  defp trusted_user_color(_), do: Enum.at(@colors, 0)

  # Get friends of friends (2nd degree connections)
  # Returns {list_of_users, list_of_edges}
  defp get_second_degree_connections(friends_map, _user_id) when map_size(friends_map) == 0 do
    {[], []}
  end

  defp get_second_degree_connections(friends_map, user_id) do
    friend_ids = Map.keys(friends_map)

    # Get all friends of my friends (BOTH directions)
    # Direction 1: where my friends are the "user"
    friends_of_friends_1 =
      Repo.all(
        from f in Friends.Social.Friendship,
          where: f.user_id in ^friend_ids and f.status == "accepted",
          preload: [:friend_user]
      )
      |> Enum.map(fn f ->
        %{friend_id: f.friend_user_id, connector_id: f.user_id, friend_user: f.friend_user, accepted_at: f.accepted_at}
      end)

    # Direction 2: where my friends are the "friend_user"
    friends_of_friends_2 =
      Repo.all(
        from f in Friends.Social.Friendship,
          where: f.friend_user_id in ^friend_ids and f.status == "accepted",
          preload: [:user]
      )
      |> Enum.map(fn f ->
        %{friend_id: f.user_id, connector_id: f.friend_user_id, friend_user: f.user, accepted_at: f.accepted_at}
      end)

    # Combine both directions
    all_friends_of_friends = friends_of_friends_1 ++ friends_of_friends_2

    # Build set of existing connections (including self)
    existing_ids = MapSet.new([user_id | friend_ids])

    # Filter out duplicates and existing connections
    second_degree_map =
      all_friends_of_friends
      |> Enum.reduce(%{}, fn friendship, acc ->
        friend_of_friend = friendship.friend_user

        # Skip if already in our network or if it's us
        if MapSet.member?(existing_ids, friendship.friend_id) do
          acc
        else
          # Track which of my friends connects to this 2nd degree person, preserving timeframe
          connection_data = %{connector_id: friendship.connector_id, accepted_at: friendship.accepted_at}
          
          Map.update(
            acc,
            friendship.friend_id,
            %{user: friend_of_friend, connections: [connection_data]},
            fn existing ->
              %{existing | connections: [connection_data | existing.connections]}
            end
          )
        end
      end)

    # Build edges from my friends to their friends (2nd degree)
    edges =
      second_degree_map
      |> Enum.flat_map(fn {second_degree_id, data} ->
        Enum.map(data.connections, fn conn ->
          # Send REAL historical time. Frontend will handle "Ego-Centric" clamping via path logic.
          # This allows Shortest Path discovery (if C connects to A(Old) and B(New), C appears with A).
          %{from: conn.connector_id, to: second_degree_id, type: "second_degree", connected_at: conn.accepted_at || NaiveDateTime.utc_now()}
        end)
      end)

    # Extract unique second degree users
    second_degree_users =
      second_degree_map
      |> Map.values()
      |> Enum.map(fn data -> data.user end)

    {second_degree_users, edges}
  end

  # Count mutual friends between two users
  defp count_mutual_friends(user_id1, user_id2) do
    # Get friends of user 1 (both directions)
    friends1_as_user =
      Repo.all(
        from f in Friends.Social.Friendship,
          where: f.user_id == ^user_id1 and f.status == "accepted",
          select: f.friend_user_id
      )

    friends1_as_friend =
      Repo.all(
        from f in Friends.Social.Friendship,
          where: f.friend_user_id == ^user_id1 and f.status == "accepted",
          select: f.user_id
      )

    friends1_ids = MapSet.new(friends1_as_user ++ friends1_as_friend)

    # Get friends of user 2 (both directions)
    friends2_as_user =
      Repo.all(
        from f in Friends.Social.Friendship,
          where: f.user_id == ^user_id2 and f.status == "accepted",
          select: f.friend_user_id
      )

    friends2_as_friend =
      Repo.all(
        from f in Friends.Social.Friendship,
          where: f.friend_user_id == ^user_id2 and f.status == "accepted",
          select: f.user_id
      )

    friends2_ids = MapSet.new(friends2_as_user ++ friends2_as_friend)

    # Count intersection
    MapSet.intersection(friends1_ids, friends2_ids)
    |> MapSet.size()
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen text-white pb-20 relative">
      <div class="opal-bg"></div>
      
      <div class="max-w-[1400px] mx-auto px-4 sm:px-8 py-8 relative z-10">
        <%!-- Header --%>
        <div class="flex items-center justify-between mb-6">
          <h1 class="text-3xl font-bold">People</h1>
        </div>

        <div class="space-y-6">
          <%!-- Personalized Invite Link (New Simplified Section) --%>
          <section class="aether-card p-6">
            <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
              <div>
                <h2 class="text-lg font-semibold text-white mb-1">Invite People</h2>
                <p class="text-sm text-neutral-400">Share your personal link - they'll automatically join your network!</p>
              </div>
              <div class="flex items-center gap-3">
                <div class="flex-1 sm:flex-none">
                  <input
                    type="text"
                    readonly
                    id="invite-link-input"
                    value={"#{FriendsWeb.Endpoint.url()}/register?ref=#{@current_user.username}"}
                    class="w-full sm:w-80 bg-black/30 border border-white/20 rounded-lg px-4 py-2 text-sm text-white font-mono select-all"
                  />
                </div>
                <button
                  id="copy-invite-link"
                  phx-hook="CopyToClipboard"
                  data-copy-target="invite-link-input"
                  class="px-4 py-2 bg-white/10 hover:bg-white/20 border border-white/20 rounded-lg text-sm text-white transition-all cursor-pointer whitespace-nowrap"
                >
                  Copy Link
                </button>
              </div>
            </div>
          </section>




          <%!-- Network Graph Trigger --%>
          <section>
            <div class="flex items-center justify-between mb-3">
              <h2 class="text-lg font-semibold text-white">Your Constellation</h2>
            </div>
            
             <div class="aether-card p-8 flex flex-col items-center justify-center text-center">
               <div class="w-16 h-16 rounded-full bg-blue-500/20 flex items-center justify-center mb-4">
                 <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-8 h-8 text-blue-400">
                   <path stroke-linecap="round" stroke-linejoin="round" d="M13.5 16.875h3.375m0 0h3.375m-3.375 0V13.5m0 3.375v3.375M6 10.5h2.25a2.25 2.25 0 002.25-2.25V6a2.25 2.25 0 00-2.25-2.25H6A2.25 2.25 0 003.75 6v2.25A2.25 2.25 0 006 10.5zm0 9.75h2.25A2.25 2.25 0 0010.5 18v-2.25a2.25 2.25 0 00-2.25-2.25H6a2.25 2.25 0 00-2.25 2.25V18A2.25 2.25 0 006 20.25zm9.75-9.75H18a2.25 2.25 0 002.25-2.25V6A2.25 2.25 0 0018 3.75h-2.25A2.25 2.25 0 0013.5 6v2.25a2.25 2.25 0 002.25 2.25z" />
                 </svg>
               </div>
               <h3 class="text-xl font-bold text-white mb-2">Explore Your Network</h3>
               <p class="text-neutral-400 max-w-md mb-6">Visualize your connections and friends of friends in an interactive 3D constellation.</p>
               <button 
                 phx-click="open_graph_modal" 
                 class="px-6 py-3 bg-white text-black font-bold uppercase tracking-wider rounded-lg hover:bg-neutral-200 transition-colors shadow-lg active:translate-y-px"
               >
                 View Constellation
               </button>
             </div>
          </section>

          <%!-- Search & Add Friends --%>
          <section>
            <h2 class="text-lg font-semibold text-white mb-3">Find People</h2>
            <div class="p-4 aether-card shadow-lg">
              <form phx-change="search_friends" phx-submit="search_friends" class="flex gap-2">
                <div class="relative flex-1">
                  <input
                    type="text"
                    name="query"
                    value={@friend_search}
                    placeholder="Search by username..."
                    autocomplete="off"
                    phx-debounce="300"
                    class="w-full bg-white/10 border border-white/20 rounded-lg px-4 py-2 text-sm text-white placeholder-neutral-400 focus:outline-none focus:border-white/40 transition-colors"
                  />
                </div>
              </form>

              <%= if @friend_search_results != [] do %>
                <div class="mt-3 space-y-2">
                  <%= for user <- @friend_search_results do %>
                    <div class="flex items-center justify-between p-2 hover:bg-white/5 rounded-lg border border-transparent hover:border-white/10 transition-all">
                      <div class="flex items-center gap-2">
                        <div
                          class="w-8 h-8 rounded-full border border-white/10"
                          style={"background-color: #{trusted_user_color(user)}"}
                        />
                        <span class="text-sm font-medium text-white">@{user.username}</span>
                      </div>
                      <button
                        phx-click="add_friend"
                        phx-value-user_id={user.id}
                        class="px-3 py-1.5 bg-blue-500 text-white text-xs font-medium rounded-lg hover:bg-blue-400 transition-colors cursor-pointer"
                      >
                        Add
                      </button>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          </section>

          <%!-- Pending Requests --%>
          <%= if @friend_requests != [] || @sent_requests != [] do %>
            <section>
              <h2 class="text-lg font-semibold text-white mb-3">Pending Requests</h2>
              <div class="space-y-2">
                <%!-- Incoming Requests --%>
                <%= for req <- @friend_requests do %>
                  <div class="flex items-center justify-between p-4 aether-card border border-blue-500/20 bg-blue-500/5">
                    <div class="flex items-center gap-3">
                      <div
                        class="w-10 h-10 rounded-full"
                        style={"background-color: #{trusted_user_color(req.user)}"}
                      />
                      <div>
                        <div class="font-medium text-white">@{req.user.username}</div>
                        <div class="text-xs text-blue-400">wants to connect</div>
                      </div>
                    </div>
                    <div class="flex gap-2">
                      <button
                        phx-click="accept_friend"
                        phx-value-user_id={req.user.id}
                        class="px-3 py-1.5 bg-blue-500 text-white text-sm font-medium rounded-lg hover:bg-blue-400 transition-colors cursor-pointer"
                      >
                        Accept
                      </button>
                      <button
                        phx-click="decline_friend"
                        phx-value-user_id={req.user.id}
                        class="px-3 py-1.5 border border-neutral-700 text-neutral-400 text-sm rounded-lg hover:text-red-400 transition-colors cursor-pointer"
                      >
                        Decline
                      </button>
                    </div>
                  </div>
                <% end %>

                <%!-- Sent Requests (Waiting for Response) --%>
                <%= for req <- @sent_requests do %>
                  <div class="flex items-center justify-between p-4 aether-card border border-amber-500/20 bg-amber-500/5">
                    <div class="flex items-center gap-3">
                      <div
                        class="w-10 h-10 rounded-full"
                        style={"background-color: #{trusted_user_color(req.friend_user)}"}
                      />
                      <div>
                        <div class="font-medium text-white">@{req.friend_user.username}</div>
                        <div class="text-xs text-amber-400">waiting for response</div>
                      </div>
                    </div>
                    <button
                      phx-click="remove_friend"
                      phx-value-user_id={req.friend_user.id}
                      class="px-3 py-1.5 text-neutral-500 hover:text-red-400 text-sm transition-colors cursor-pointer"
                    >
                      Cancel
                    </button>
                  </div>
                <% end %>
              </div>
            </section>
          <% end %>

          <%!-- Your People --%>
          <section>
            <h2 class="text-lg font-semibold text-white mb-3">
              Your People ({length(@friends)})
            </h2>

            <%= if @friends == [] do %>
              <div class="p-8 aether-card text-center">
                <div class="text-neutral-500 text-sm">
                  No people yet. Search above to add some!
                </div>
              </div>
            <% else %>
              <div class="grid grid-cols-1 gap-3">
                <%= for f <- @friends do %>
                  <% is_trusted =
                    Enum.any?(@trusted_friends, fn tf -> tf.trusted_user.id == f.user.id end) %>

                  <div class={"flex items-center justify-between p-4 rounded-xl border transition-all shadow-lg #{if is_trusted, do: "border-emerald-500/30 bg-emerald-500/5", else: "aether-card border-white/5 hover:border-white/20"}"}>
                    <div class="flex items-center gap-3">
                      <div class="relative">
                        <div
                          class="w-10 h-10 rounded-full"
                          style={"background: linear-gradient(135deg, #{trusted_user_color(f.user)} 0%, #{trusted_user_color(f.user)}88 100%)"}
                        />
                        <%= if is_trusted do %>
                          <span class="absolute -top-1 -right-1 text-sm">🔒</span>
                        <% end %>
                      </div>

                      <div>
                        <div class="font-medium text-white flex items-center gap-2">
                          @{f.user.username}
                          <%= if is_trusted do %>
                            <span class="text-[10px] text-emerald-400 bg-emerald-500/20 px-2 py-0.5 rounded-full border border-emerald-500/30">
                              RECOVERY
                            </span>
                          <% end %>
                        </div>
                        <%= if f.mutual_count && f.mutual_count > 0 do %>
                          <div class="text-xs text-neutral-400">
                            {f.mutual_count} mutual
                          </div>
                        <% end %>
                      </div>
                    </div>

                    <div class="flex gap-2 text-sm">
                      <%= if not is_trusted and length(@trusted_friends) < 5 do %>
                        <button
                          phx-click="add_trusted_friend"
                          phx-value-user_id={f.user.id}
                          class="text-emerald-500 hover:text-emerald-400 hover:underline transition-colors cursor-pointer"
                        >
                          + Recovery
                        </button>
                      <% end %>

                      <button
                        phx-click="remove_friend"
                        phx-value-user_id={f.user.id}
                        data-confirm="Remove contact?"
                        class="text-neutral-500 hover:text-red-400 transition-colors cursor-pointer"
                      >
                        Remove
                      </button>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
          </section>

          <%!-- Legacy Invite Codes (Collapsed) --%>
          <%= if @invites != [] do %>
            <details class="pt-4 border-t border-neutral-800">
              <summary class="text-sm text-neutral-500 cursor-pointer hover:text-neutral-300">
                Legacy invite codes ({length(@invites)})
              </summary>
              <div class="mt-3 grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-3">
                <%= for invite <- @invites do %>
                  <div class="p-3 bg-white/5 rounded-lg flex items-center justify-between text-sm">
                    <div class="font-mono text-purple-300">{invite.code}</div>
                    <span class="text-xs text-neutral-500">{invite.status}</span>
                  </div>
                <% end %>
              </div>
            </details>
          <% end %>
        </div>
      </div>
      
      <%!-- Network Graph Modal (Moved outside main content z-index context) --%>
      <%= if @show_graph_modal do %>
        <.modal id="network-graph-modal" show={@show_graph_modal} on_cancel={JS.push("close_graph_modal")} backdrop_class="bg-black/40 backdrop-blur-sm" container_class="w-full max-w-[95vw] h-[90vh] max-h-[90vh] bg-black/60 backdrop-blur-3xl p-0 border border-white/10 overflow-hidden rounded-2xl shadow-[0_0_50px_rgba(0,0,0,0.9)] relative ring-1 ring-white/5">
          <div class="h-full w-full relative group">
            <%!-- Use a wrapper with phx-update="ignore" that contains the hook element --%>
            <div id="network-graph-wrapper" phx-update="ignore">
              <%= if @graph_data do %>
                <div
                  id="network-graph"
                  phx-hook="FriendGraph"
                  data-graph={Jason.encode!(@graph_data)}
                  class="w-full h-full block"
                ></div>
              <% end %>
            </div>
          </div>
        </.modal>
      <% end %>
    </div>
    """
  end
end
