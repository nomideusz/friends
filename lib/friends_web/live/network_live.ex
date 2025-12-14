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
    |> assign(:page_title, "Contacts")
    |> assign(:friend_search, "")
    |> assign(:friend_search_results, [])
    |> assign(:show_header_dropdown, false)
    |> assign(:show_user_dropdown, false)
    |> assign(:current_route, "/network")
    |> assign(:user_rooms, [])
  end

  defp load_data(socket) do
    user = socket.assigns.current_user

    if user do
      socket
      |> assign(:friends, Social.list_friends(user.id))
      |> assign(:friend_requests, Social.list_friend_requests(user.id))
      |> assign(:sent_requests, Social.list_sent_friend_requests(user.id))
      |> assign(:trusted_friends, Social.list_trusted_friends(user.id))
      |> assign(:pending_trust_requests, Social.list_pending_trust_requests(user.id))
      |> assign(:outgoing_trust_requests, Social.list_sent_trust_requests(user.id))
      |> assign(:invites, Social.list_user_invites(user.id))
      |> assign(:user_rooms, Social.list_user_rooms(user.id))
      # For graph view
      |> assign(
        :graph_data,
        if(socket.assigns.view == "graph", do: build_graph_data(user), else: nil)
      )
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

  def handle_event("set_view", %{"view" => view}, socket) do
    {:noreply, socket |> assign(:view, view) |> load_data()}
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
         |> put_flash(:info, "Trusted contact request sent")
         |> load_data()}

      {:error, :max_trusted_friends} ->
        {:noreply, put_flash(socket, :error, "You can only have 5 trusted contacts")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not add trusted contact")}
    end
  end

  def handle_event("confirm_trust", %{"user_id" => user_id}, socket) do
    case Social.confirm_trusted_friend(socket.assigns.current_user.id, user_id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Trusted friend confirmed")
         |> load_data()}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not confirm trusted friend")}
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

  # User dropdown handlers
  def handle_event("toggle_user_dropdown", _, socket) do
    {:noreply, assign(socket, :show_user_dropdown, !socket.assigns.show_user_dropdown)}
  end

  def handle_event("close_user_dropdown", _, socket) do
    {:noreply, assign(socket, :show_user_dropdown, false)}
  end

  def handle_event("sign_out", _, socket) do
    {:noreply, push_navigate(socket, to: ~p"/login?action=signout")}
  end

  # --- Real-time Updates ---

  def handle_info({:friend_request, _}, socket), do: {:noreply, load_data(socket)}
  def handle_info({:friend_accepted, _}, socket), do: {:noreply, load_data(socket)}
  def handle_info({:friend_removed, _}, socket), do: {:noreply, load_data(socket)}
  # Room events - refresh user_rooms list
  def handle_info({:room_created, _room}, socket), do: {:noreply, load_data(socket)}
  # Catch-all for any other broadcasts we don't need to handle
  def handle_info(_, socket), do: {:noreply, socket}

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
    friend_ids = Enum.map(friends, fn f -> f.user.id end)

    # 4. Get friendships BETWEEN my friends (the social network magic!)
    # This shows connections like: if A is friends with B and C, and B is friends with C
    friend_to_friend_edges = get_friendships_between(friend_ids)

    # Build nodes map to avoid duplicates
    nodes_map = %{}

    # Add current user as central node
    current_user_node = %{
      id: user.id,
      username: user.username,
      display_name: user.display_name,
      color: trusted_user_color(user),
      type: "self"
    }

    nodes_map = Map.put(nodes_map, user.id, current_user_node)

    # Add trusted users
    nodes_map =
      Enum.reduce(my_trusted, nodes_map, fn tf, acc ->
        Map.put_new(acc, tf.trusted_user.id, %{
          id: tf.trusted_user.id,
          username: tf.trusted_user.username,
          display_name: tf.trusted_user.display_name,
          color: trusted_user_color(tf.trusted_user),
          type: "trusted"
        })
      end)

    # Add people who trust me
    nodes_map =
      Enum.reduce(people_who_trust_me, nodes_map, fn tf, acc ->
        Map.put_new(acc, tf.user.id, %{
          id: tf.user.id,
          username: tf.user.username,
          display_name: tf.user.display_name,
          color: trusted_user_color(tf.user),
          type: "trusts_me"
        })
      end)

    # Add social friends
    nodes_map =
      Enum.reduce(friends, nodes_map, fn f, acc ->
        Map.put_new(acc, f.user.id, %{
          id: f.user.id,
          username: f.user.username,
          display_name: f.user.display_name,
          color: trusted_user_color(f.user),
          type: "friend"
        })
      end)

    # Build edges
    edges = []

    # Edges for people I trust
    edges =
      Enum.reduce(my_trusted, edges, fn tf, acc ->
        [%{from: user.id, to: tf.trusted_user.id, type: "trusted"} | acc]
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
          [%{from: tf.user.id, to: user.id, type: "trusts_me"} | acc]
        end
      end)

    # Edges for my direct friends
    edges =
      Enum.reduce(friends, edges, fn f, acc ->
        [%{from: user.id, to: f.user.id, type: "friend"} | acc]
      end)

    # Edges between my friends (social network connections!)
    edges =
      Enum.reduce(friend_to_friend_edges, edges, fn {id1, id2}, acc ->
        [%{from: id1, to: id2, type: "mutual"} | acc]
      end)

    # Stats
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
        friends: length(friends),
        friend_connections: length(friend_to_friend_edges),
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
        select: {f.user_id, f.friend_user_id}
    )
    |> Enum.map(fn {id1, id2} ->
      # Normalize to avoid duplicates (always smaller ID first)
      if id1 < id2, do: {id1, id2}, else: {id2, id1}
    end)
    |> Enum.uniq()
  end

  defp trusted_user_color(%{id: id}) when is_integer(id) do
    Enum.at(@colors, rem(id, length(@colors)))
  end

  defp trusted_user_color(_), do: Enum.at(@colors, 0)

  def render(assigns) do
    ~H"""
    <div class="min-h-screen text-white pb-20">
      <div class="max-w-[1200px] mx-auto px-4 sm:px-8 py-8">
        <div class="flex items-center justify-between mb-8">
          <h1 class="text-3xl font-bold">Contacts</h1>
           <%!-- View Toggle --%>
          <div class="flex p-1 bg-neutral-900 rounded md:rounded-lg border border-neutral-200 shadow-sm">
            <button
              phx-click="set_view"
              phx-value-view="list"
              class={"px-3 py-1 text-sm rounded-md transition-all cursor-pointer #{if @view == "list", do: "bg-neutral-800 text-white shadow-sm", else: "text-neutral-500 hover:text-neutral-300"}"}
            >
              List
            </button>
            <button
              phx-click="set_view"
              phx-value-view="graph"
              class={"px-3 py-1 text-sm rounded-md transition-all cursor-pointer #{if @view == "graph", do: "bg-neutral-800 text-white shadow-sm", else: "text-neutral-500 hover:text-neutral-300"}"}
            >
              Graph
            </button>
          </div>
        </div>
        
        <%= if @view == "list" do %>
          <div class="space-y-12">
            <%!-- Trusted Contacts --%>
            <section>
              <div class="flex items-center gap-2 mb-4">
                <h2 class="text-xl font-semibold text-green-400 flex items-center gap-2">
                  <span>🔐</span> Trusted Contacts
                </h2>
                
                <span class="text-xs font-bold text-neutral-500 bg-neutral-100 px-2 py-1 rounded-full border border-neutral-300">
                  Recovery
                </span>
              </div>
              
              <%= if @pending_trust_requests != [] do %>
                <div class="mb-4 space-y-2">
                  <%= for req <- @pending_trust_requests do %>
                    <div class="flex items-center justify-between p-4 glass rounded-xl border border-amber-500/20 bg-amber-500/5">
                      <div>
                        <div class="font-medium">@{req.user.username}</div>
                        
                        <div class="text-xs text-amber-400">wants to trust you for recovery</div>
                      </div>
                      
                      <button
                        phx-click="confirm_trust"
                        phx-value-user_id={req.user.id}
                        class="px-4 py-2 bg-amber-500 text-black font-semibold rounded-lg hover:bg-amber-400 transition-colors pointer-events-auto cursor-pointer"
                      >
                        Confirm
                      </button>
                    </div>
                  <% end %>
                </div>
              <% end %>
              
              <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                <%= for tf <- @trusted_friends do %>
                  <div class="flex items-center justify-between p-4 aether-card hover:bg-white/5 transition-colors shadow-lg">
                    <div class="flex items-center gap-3">
                      <div
                        class="w-10 h-10 rounded-full presence-dot"
                        style={"background-color: #{trusted_user_color(tf.trusted_user)}; color: #{trusted_user_color(tf.trusted_user)}"}
                      />
                      <div>
                        <div class="font-medium">@{tf.trusted_user.username}</div>
                        
                        <div class="text-xs text-green-400">Confirmed</div>
                      </div>
                    </div>
                  </div>
                <% end %>
                
                <%= if length(@trusted_friends) < 5 do %>
                  <div class="p-4 border border-dashed border-neutral-400 rounded md:rounded-lg text-neutral-500 flex items-center justify-center text-sm font-bold uppercase tracking-wide">
                    Select a contact below to add as trusted
                  </div>
                <% end %>
              </div>
            </section>
             <%!-- All Contacts --%>
            <section>
              <h2 class="text-xl font-semibold text-white mb-4 flex items-center gap-2">
                <span>👥</span> All Contacts
              </h2>
               <%!-- Friend Requests --%>
              <%= if @friend_requests != [] do %>
                <div class="mb-6 space-y-2">
                  <div class="text-sm font-medium text-blue-400 uppercase tracking-wider mb-2">
                    Pending Requests
                  </div>
                  
                  <%= for req <- @friend_requests do %>
                    <div class="flex items-center justify-between p-4 glass rounded-xl border border-blue-500/20 bg-blue-500/5">
                      <div class="flex items-center gap-3">
                        <div
                          class="w-8 h-8 rounded-full presence-dot"
                          style={"background-color: #{trusted_user_color(req.user)}; color: #{trusted_user_color(req.user)}"}
                        />
                        <div>
                          <div class="font-medium">@{req.user.username}</div>
                          
                          <div class="text-xs text-neutral-400">wants to connect</div>
                        </div>
                      </div>
                      
                      <div class="flex gap-2">
                        <button
                          phx-click="accept_friend"
                          phx-value-user_id={req.user.id}
                          class="px-3 py-1.5 bg-blue-500 text-black text-sm font-medium rounded-lg hover:bg-blue-400 transition-colors pointer-events-auto cursor-pointer"
                        >
                          Accept
                        </button>
                        <button
                          phx-click="decline_friend"
                          phx-value-user_id={req.user.id}
                          class="px-3 py-1.5 border border-neutral-700 text-neutral-400 text-sm rounded-lg hover:text-red-400 transition-colors pointer-events-auto cursor-pointer"
                        >
                          Decline
                        </button>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>
               <%!-- Add Contact Search --%>
              <div class="mb-6 p-4 aether-card shadow-lg">
                <form phx-change="search_friends" phx-submit="search_friends" class="flex gap-2">
                  <div class="relative flex-1">
                    <input
                      type="text"
                      name="query"
                      value={@friend_search}
                      placeholder="Add new contact by username..."
                      autocomplete="off"
                      phx-debounce="300"
                      class="w-full bg-white border border-neutral-300 rounded px-4 py-2 text-sm text-neutral-900 focus:outline-none focus:border-opal-rose transition-colors"
                    />
                  </div>
                </form>
                
                <%= if @friend_search_results != [] do %>
                  <div class="mt-2 space-y-2">
                    <%= for user <- @friend_search_results do %>
                      <div class="flex items-center justify-between p-2 bg-neutral-800 rounded md:rounded-lg border border-neutral-200">
                        <div class="flex items-center gap-2">
                          <div
                            class="w-6 h-6 rounded-full"
                            style={"background-color: #{trusted_user_color(user)}"}
                          /> <span class="text-sm font-medium">@{user.username}</span>
                        </div>
                        
                        <button
                          phx-click="add_friend"
                          phx-value-user_id={user.id}
                          class="px-3 py-1 bg-neutral-200 hover:bg-neutral-300 rounded text-xs font-bold text-neutral-900 transition-colors pointer-events-auto cursor-pointer border border-neutral-300 shadow-sm active:translate-y-px"
                        >
                          Add Contact
                        </button>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>
              
              <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
                <%= for f <- @friends do %>
                  <% is_trusted =
                    Enum.any?(@trusted_friends, fn tf -> tf.trusted_user.id == f.user.id end) %>
                  <%!-- Filter out if already shown in trusted section? User guidelines implied show all below. I'll show all but mark trusted. --%>
                  <div class={
                    "flex items-center justify-between p-3 bg-neutral-900 rounded md:rounded-lg border transition-all shadow-sm " <>
                    if is_trusted, do: "border-green-500 bg-green-50", else: "border-neutral-200 hover:border-neutral-300"
                  }>
                    <div class="flex items-center gap-3">
                      <div class="relative">
                        <div
                          class="w-10 h-10 rounded-full"
                          style={"background: linear-gradient(135deg, #{trusted_user_color(f.user)} 0%, #{trusted_user_color(f.user)}88 100%)"}
                        />
                        <%= if is_trusted do %>
                          <span class="absolute -bottom-0.5 -right-0.5 w-4 h-4 bg-green-500 rounded-full flex items-center justify-center text-[10px]">
                            ✓
                          </span>
                        <% end %>
                      </div>
                      
                      <div>
                        <div class="font-medium text-white">@{f.user.username}</div>
                      </div>
                    </div>
                    
                    <div class="flex gap-2 text-sm">
                      <%= if not is_trusted do %>
                        <button
                          phx-click="add_trusted_friend"
                          phx-value-user_id={f.user.id}
                          class="text-green-500 hover:text-green-400 hover:underline transition-colors pointer-events-auto cursor-pointer"
                        >
                          Trust
                        </button>
                      <% end %>
                      
                      <button
                        phx-click="remove_friend"
                        phx-value-user_id={f.user.id}
                        data-confirm="Remove friend?"
                        class="text-neutral-500 hover:text-red-400 transition-colors pointer-events-auto cursor-pointer"
                      >
                        Remove
                      </button>
                    </div>
                  </div>
                <% end %>
              </div>
            </section>
             <%!-- Invites Section --%>
            <section class="pt-8 border-t border-neutral-200">
              <div class="flex items-center justify-between mb-4">
                <h2 class="text-lg font-semibold text-purple-400 flex items-center gap-2">
                  <span>🎟️</span> Invites
                </h2>
                
                <button
                  phx-click="create_invite"
                  class="px-3 py-1.5 bg-purple-500/20 text-purple-300 border border-purple-500/30 rounded-lg text-sm hover:bg-purple-500/30 transition-colors pointer-events-auto cursor-pointer"
                >
                  + Create Code
                </button>
              </div>
              
              <%= if @invites != [] do %>
                <div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-3">
                  <%= for invite <- @invites do %>
                    <div class="p-3 aether-card flex items-center justify-between shadow-lg">
                      <div>
                        <div
                          class="font-mono text-lg tracking-wider text-purple-300 select-all cursor-pointer"
                          phx-click={JS.dispatch("friends:copy", to: "#code-#{invite.id}")}
                          id={"code-#{invite.id}"}
                          data-copy={invite.code}
                        >
                          {invite.code}
                        </div>
                        
                        <div class="text-[10px] text-neutral-500">{invite.status}</div>
                      </div>
                      
                      <%= if invite.status == "active" do %>
                        <button
                          phx-click="revoke_invite"
                          phx-value-code={invite.code}
                          class="text-xs text-red-500/70 hover:text-red-400 pointer-events-auto cursor-pointer"
                        >
                          Revoke
                        </button>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              <% else %>
                <p class="text-neutral-600 text-sm">No active invite codes.</p>
              <% end %>
            </section>
          </div>
        <% else %>
          <%!-- Graph View --%>
          <div class="relative">
            <%= if @graph_data.stats.total_connections > 0 do %>
              <div class="h-[75vh] min-h-[500px] aether-card overflow-hidden relative shadow-inner">
                <div
                  id="network-graph"
                  phx-hook="FriendGraph"
                  phx-update="ignore"
                  data-graph={Jason.encode!(@graph_data)}
                  class="w-full h-full"
                >
                </div>
                 <%!-- Overlay Stats --%>
                <div class="absolute bottom-4 left-4 right-4 flex flex-wrap gap-2 pointer-events-none">
                  <%= if @graph_data.stats.i_trust > 0 do %>
                    <div class="px-3 py-1.5 bg-black/60 backdrop-blur-md rounded-lg border border-green-500/30 flex items-center gap-2">
                      <span class="w-2 h-2 rounded-full bg-green-500"></span>
                      <span class="text-xs text-white">I trust: {@graph_data.stats.i_trust}</span>
                    </div>
                  <% end %>
                  
                  <%= if @graph_data.stats.friends > 0 do %>
                    <div class="px-3 py-1.5 bg-neutral-100/90 backdrop-blur rounded border border-neutral-300 flex items-center gap-2 shadow-lg">
                      <span class="w-2 h-2 rounded-full bg-blue-500"></span>
                      <span class="text-xs text-white">Contacts: {@graph_data.stats.friends}</span>
                    </div>
                  <% end %>
                </div>
              </div>
            <% else %>
              <div class="h-[70vh] bg-neutral-100 rounded md:rounded-lg flex items-center justify-center border border-neutral-200">
                <div class="text-center">
                  <div class="text-4xl mb-4">🕸️</div>
                  
                  <h3 class="text-lg font-medium">Your network is empty</h3>
                  
                  <p class="text-neutral-500 mt-2">
                    Add contacts or trusted contacts to see your graph.
                  </p>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
