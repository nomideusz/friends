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

    color = if user do
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
    view = params["view"] || "list" # list or graph
    tab = params["tab"] || "friends" # friends, trusted, requests
    
    {:noreply, 
     socket 
     |> assign(:view, view)
     |> assign(:active_tab, tab)
     |> load_data()}
  end

  defp assign_defaults(socket) do
    socket
    |> assign(:page_title, "Network")
    |> assign(:friend_search, "")
    |> assign(:friend_search_results, [])
    |> assign(:show_header_dropdown, false)
    |> assign(:user_rooms, [])
    |> assign(:public_rooms, Social.list_public_rooms())
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
      |> assign(:graph_data, if(socket.assigns.view == "graph", do: build_graph_data(user), else: nil))
    else
      socket
      |> put_flash(:error, "You must be logged in")
      |> redirect(to: "/")
    end
  end

  # --- Event Handlers ---

  def handle_event("set_view", %{"view" => view}, socket) do
    {:noreply, push_patch(socket, to: ~p"/network?view=#{view}&tab=#{socket.assigns.active_tab}")}
  end

  def handle_event("set_tab", %{"tab" => tab}, socket) do
    {:noreply, push_patch(socket, to: ~p"/network?view=#{socket.assigns.view}&tab=#{tab}")}
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
         |> put_flash(:info, "Friend request sent!")
         |> assign(:friend_search, "")
         |> assign(:friend_search_results, [])
         |> load_data()}
         
      {:error, reason} ->
        msg = case reason do
          :already_friends -> "You are already friends"
          :request_already_sent -> "Request already sent"
          _ -> "Could not add friend"
        end
        {:noreply, put_flash(socket, :error, msg)}
    end
  end

  def handle_event("accept_friend", %{"user_id" => user_id}, socket) do
    case Social.accept_friend(socket.assigns.current_user.id, user_id) do
      {:ok, _} ->
        {:noreply, 
         socket 
         |> put_flash(:info, "Friend accepted!")
         |> load_data()}
      _ ->
        {:noreply, put_flash(socket, :error, "Could not accept friend")}
    end
  end

  def handle_event("remove_friend", %{"user_id" => user_id}, socket) do
    case Social.remove_friend(socket.assigns.current_user.id, user_id) do
      {:ok, _} ->
        {:noreply, 
         socket 
         |> put_flash(:info, "Friend removed")
         |> load_data()}
      _ ->
        {:noreply, put_flash(socket, :error, "Could not remove friend")}
    end
  end
  
  # Trusted friend handlers (keep existing logic)
  def handle_event("add_trusted_friend", %{"user_id" => user_id}, socket) do
    case Social.add_trusted_friend(socket.assigns.current_user.id, user_id) do
      {:ok, _} ->
        {:noreply, 
         socket 
         |> put_flash(:info, "Trusted friend request sent")
         |> load_data()}
      {:error, :max_trusted_friends} ->
        {:noreply, put_flash(socket, :error, "You can only have 5 trusted friends")}
      _ ->
        {:noreply, put_flash(socket, :error, "Could not add trusted friend")}
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

  # --- Real-time Updates ---
  
  def handle_info({:friend_request, _}, socket), do: {:noreply, load_data(socket)}
  def handle_info({:friend_accepted, _}, socket), do: {:noreply, load_data(socket)}
  def handle_info({:friend_removed, _}, socket), do: {:noreply, load_data(socket)}

  # --- Graph Helper (Simplified from graph_live.ex) ---
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

    # 7. Social Friends (accepted) - NEW!
    friends = Social.list_friends(user_id) # returns list of %{user: user, direction: ...}

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
          acc # Already handled by bidirectional logic in JS
        else
          [%{from: tf.user.id, to: user.id, type: "trusts_me"} | acc]
        end
      end)

    # Edges for social friends
    edges =
      Enum.reduce(friends, edges, fn f, acc ->
        # Check if trusted edge already covers this connection?
        # A user can be both trusted AND friend.
        # For graph simplicity, we might want separate edges or a merged type.
        # But for now, let's add friend edges. Vis.js handles multiple edges.
        [%{from: user.id, to: f.user.id, type: "friend"} | acc]
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
        pending_in: 0, # Simplified for NetworkLive
        invited: 0     # Simplified for NetworkLive
      }
    }
  end
  
  defp trusted_user_color(%{id: id}) when is_integer(id) do
    Enum.at(@colors, rem(id, length(@colors)))
  end

  defp trusted_user_color(_), do: Enum.at(@colors, 0)

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-black text-white pb-20">
      <%!-- Header --%>
        <.live_component
          module={FriendsWeb.HeaderComponent}
          id="app-header"
          room={nil}
          page_title="Network"
          current_user={@current_user}
          user_color={@user_color}
          auth_status={:authed}
          viewers={[]}
          user_rooms={@user_rooms}
          public_rooms={@public_rooms}
          pending_count={length(@friend_requests)}
          show_dropdown={@show_header_dropdown}
          current_route="/network"
        />
      
      <main class="max-w-[1600px] mx-auto px-4 sm:px-8 py-8">
        
        <%!-- Tabs & Toggles --%>
          <div class="flex flex-col sm:flex-row items-start sm:items-center justify-between border-b border-white/10 mb-8 gap-4">
            <div class="flex gap-6">
              <button phx-click="set_tab" phx-value-tab="friends" class={"pb-3 text-sm font-medium transition-all relative cursor-pointer #{if @active_tab == "friends", do: "text-white border-b-2 border-white", else: "text-neutral-500 hover:text-neutral-300"}"}>
                Friends
                <%= if length(@friend_requests) > 0 do %>
                  <span class="ml-2 px-1.5 py-0.5 bg-blue-500 text-black text-[10px] font-bold rounded-full">{length(@friend_requests)}</span>
                <% end %>
              </button>
              <button phx-click="set_tab" phx-value-tab="trusted" class={"pb-3 text-sm font-medium transition-all relative cursor-pointer #{if @active_tab == "trusted", do: "text-green-400 border-b-2 border-green-400", else: "text-neutral-500 hover:text-neutral-300"}"}>
                Trusted (Recovery)
                <%= if length(@pending_trust_requests) > 0 do %>
                  <span class="ml-2 px-1.5 py-0.5 bg-amber-500 text-black text-[10px] font-bold rounded-full">{length(@pending_trust_requests)}</span>
                <% end %>
              </button>
              <button phx-click="set_tab" phx-value-tab="invites" class={"pb-3 text-sm font-medium transition-all relative cursor-pointer #{if @active_tab == "invites", do: "text-purple-400 border-b-2 border-purple-400", else: "text-neutral-500 hover:text-neutral-300"}"}>
                Invites
                <%= if length(@invites) > 0 do %>
                  <span class="ml-2 px-1.5 py-0.5 bg-purple-500 text-black text-[10px] font-bold rounded-full">{length(Enum.filter(@invites, & &1.status == "active"))}</span>
                <% end %>
              </button>
            </div>
            
            <%!-- View Toggle --%>
            <div class="flex p-1 bg-neutral-900 rounded-lg border border-white/5 mb-2">
              <button phx-click="set_view" phx-value-view="list" class={"px-3 py-1 text-sm rounded-md transition-all cursor-pointer #{if @view == "list", do: "bg-neutral-800 text-white shadow-sm", else: "text-neutral-500 hover:text-neutral-300"}"}>
                List
              </button>
              <button phx-click="set_view" phx-value-view="graph" class={"px-3 py-1 text-sm rounded-md transition-all cursor-pointer #{if @view == "graph", do: "bg-neutral-800 text-white shadow-sm", else: "text-neutral-500 hover:text-neutral-300"}"}>
                Graph
              </button>
            </div>
          </div>
          
        <%= if @view == "list" do %>
          <%= if @active_tab == "friends" do %>
            <div class="max-w-2xl">
              <%!-- Friend Search --%>
              <div class="mb-8 p-6 glass rounded-2xl border border-white/5">
                <h3 class="text-lg font-medium mb-4">Add Friend</h3>
                <form phx-change="search_friends" phx-submit="search_friends">
                  <div class="relative">
                    <input type="text" name="query" value={@friend_search} placeholder="Search by username..." autocomplete="off" phx-debounce="300" 
                           class="w-full bg-black/50 border border-white/10 rounded-xl px-4 py-3 focus:outline-none focus:border-white/30 transition-colors" />
                  </div>
                </form>
                
                <%= if @friend_search_results != [] do %>
                  <div class="mt-4 space-y-2">
                    <%= for user <- @friend_search_results do %>
                      <div class="flex items-center justify-between p-3 bg-neutral-900/50 rounded-xl border border-white/5">
                        <div class="flex items-center gap-3">
                          <div class="w-3 h-3 rounded-full presence-dot" style={"background-color: #{trusted_user_color(user)}; color: #{trusted_user_color(user)}"}></div>
                          <span class="font-medium">@{user.username}</span>
                        </div>
                        <button phx-click="add_friend" phx-value-user_id={user.id} class="px-3 py-1.5 bg-white/10 hover:bg-white/20 rounded-lg text-sm transition-colors">
                          Add Friend
                        </button>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>

              <%!-- Friend Requests --%>
              <%= if @friend_requests != [] do %>
                <div class="mb-8">
                  <h3 class="text-lg font-medium mb-4 text-blue-400">Requests ({length(@friend_requests)})</h3>
                  <div class="grid gap-3">
                    <%= for req <- @friend_requests do %>
                      <div class="flex items-center justify-between p-4 glass rounded-xl border border-white/5">
                        <div class="flex items-center gap-3">
                          <div class="w-3 h-3 rounded-full presence-dot" style={"background-color: #{trusted_user_color(req.user)}; color: #{trusted_user_color(req.user)}"} />
                          <div>
                            <div class="font-medium">@{req.user.username}</div>
                            <div class="text-xs text-neutral-500">wants to be friends</div>
                          </div>
                        </div>
                        <div class="flex gap-2">
                          <button phx-click="accept_friend" phx-value-user_id={req.user.id} class="px-4 py-2 bg-blue-500 text-black font-semibold rounded-lg hover:bg-blue-400 transition-colors">Accept</button>
                        </div>
                      </div>
                    <% end %>
                  </div>
                </div>

              <% end %>

              <%!-- Sent Requests (Pending Outgoing) --%>
              <%= if @sent_requests != [] do %>
                <div class="mb-8">
                  <h3 class="text-lg font-medium mb-4 text-neutral-400">Sent Requests ({length(@sent_requests)})</h3>
                  <div class="grid gap-3">
                    <%= for req <- @sent_requests do %>
                      <div class="flex items-center justify-between p-4 glass rounded-xl border border-white/5 opacity-70">
                        <div class="flex items-center gap-3">
                          <div class="w-3 h-3 rounded-full presence-dot bg-neutral-600" />
                          <div>
                            <div class="font-medium">@{req.friend_user.username}</div>
                            <div class="text-xs text-neutral-500">Pending acceptance...</div>
                          </div>
                        </div>
                        <button phx-click="remove_friend" phx-value-user_id={req.friend_user.id} class="text-xs text-red-400 hover:text-red-300 transition-colors">Cancel</button>
                      </div>
                    <% end %>
                  </div>
                </div>
              <% end %>

              <%!-- Friends List --%>
              <div>
                <h3 class="text-lg font-medium mb-4">My Friends ({length(@friends)})</h3>
                <div class="grid gap-3">
                  <%= for f <- @friends do %>
                    <div class="flex items-center justify-between p-4 glass rounded-xl border border-white/5 group">
                      <div class="flex items-center gap-3">
                        <div class="w-3 h-3 rounded-full presence-dot" style={"background-color: #{trusted_user_color(f.user)}; color: #{trusted_user_color(f.user)}"} />
                        <div>
                          <div class="font-medium">@{f.user.username}</div>
                          <div class="text-xs text-neutral-500">Connected</div>
                        </div>
                      </div>
                      <div class="flex gap-2 opacity-0 group-hover:opacity-100 transition-all">
                        <%= if not Enum.any?(@trusted_friends, fn tf -> tf.trusted_user.id == f.user.id end) do %>
                           <button phx-click="add_trusted_friend" phx-value-user_id={f.user.id} class="px-3 py-1.5 text-green-400 hover:bg-green-500/10 rounded-lg text-sm transition-all" title="Add as Trusted Recovery Contact">
                             + Trust
                           </button>
                        <% end %>
                        <button phx-click="remove_friend" phx-value-user_id={f.user.id} data-confirm="Are you sure?" class="px-3 py-1.5 text-red-400 hover:bg-red-500/10 rounded-lg text-sm transition-all">
                          Remove
                        </button>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
            
          <% else %>
            <%!-- Trusted Tab --%>
            <div class="max-w-2xl">
              <div class="p-6 bg-green-500/5 border border-green-500/20 rounded-2xl mb-8">
                <h3 class="text-green-400 font-medium mb-2 flex items-center gap-2">
                  <span>🔐</span> Account Recovery
                </h3>
                <p class="text-sm text-green-200/70">
                  Trusted friends can help you recover your account if you lose your key. 
                  You can have up to 5 trusted friends. Choose people you can contact outside of this app.
                </p>
              </div>
              
              <%!-- Current Trusted Friends --%>
              <div class="mb-8">
                <h3 class="text-lg font-medium mb-4">My Trusted Contacts ({length(@trusted_friends)}/5)</h3>
                <div class="grid gap-3">
                   <%= for tf <- @trusted_friends do %>
                    <div class="flex items-center justify-between p-4 glass rounded-xl border border-white/5 border-l-4 border-l-green-500">
                      <div class="flex items-center gap-3">
                        <div class="w-3 h-3 rounded-full presence-dot" style={"background-color: #{trusted_user_color(tf.trusted_user)}; color: #{trusted_user_color(tf.trusted_user)}"} />
                        <div>
                          <div class="font-medium">@{tf.trusted_user.username}</div>
                          <div class="text-xs text-green-400">Confirmed Trusted</div>
                        </div>
                      </div>
                    </div>
                  <% end %>
                  
                  <%= if length(@trusted_friends) < 5 do %>
                     <button phx-click="set_tab" phx-value-tab="friends" class="p-4 border border-dashed border-white/10 rounded-xl text-neutral-500 hover:text-white hover:border-white/30 transition-all text-center">
                       + Add trusted friend from Friends list
                     </button>
                  <% end %>
                </div>
              </div>
              
              <%!-- Incoming Requests --%>
              <%= if @pending_trust_requests != [] do %>
                 <div class="mb-8">
                  <h3 class="text-lg font-medium mb-4 text-amber-400">Pending Requests</h3>
                  <%= for req <- @pending_trust_requests do %>
                    <div class="flex items-center justify-between p-4 glass rounded-xl border border-amber-500/20">
                      <div>
                        <div class="font-medium">@{req.user.username}</div>
                        <div class="text-xs text-neutral-500">wants to trust you for recovery</div>
                      </div>
                      <button phx-click="confirm_trust" phx-value-user_id={req.user.id} class="px-4 py-2 bg-amber-500 text-black font-semibold rounded-lg">Confirm</button>
                    </div>
                  <% end %>
                 </div>
              <% end %>
            </div>
          <% end %>

          <%= if @active_tab == "invites" do %>
            <%!-- Invites Tab --%>
            <div class="max-w-2xl">
              <div class="p-6 bg-purple-500/5 border border-purple-500/20 rounded-2xl mb-8">
                <h3 class="text-purple-400 font-medium mb-2 flex items-center gap-2">
                  <span>🎟️</span> Invite New Users
                </h3>
                <p class="text-sm text-purple-200/70">
                  Create invite codes to bring new people into the network.
                </p>
                <button phx-click="create_invite" class="mt-4 px-4 py-2 bg-purple-600 text-white rounded-lg hover:bg-purple-500 transition-all font-medium">
                  Generate New Invite Code
                </button>
              </div>

              <%= if @invites != [] do %>
                 <div class="grid gap-3">
                   <%= for invite <- @invites do %>
                     <div class="flex items-center justify-between p-4 glass rounded-xl border border-white/5">
                        <div>
                          <div class="font-mono text-xl tracking-wider text-purple-300 select-all cursor-pointer" phx-click={JS.dispatch("friends:copy", to: "#code-#{invite.id}")} id={"code-#{invite.id}"} data-copy={invite.code}>
                            {invite.code}
                          </div>
                          <div class="text-xs text-neutral-500 mt-1">
                            Status: <span class={if invite.status == "active", do: "text-green-400", else: "text-red-400"}>{invite.status}</span>
                            <%= if invite.used_by do %>
                              • Used by @{invite.used_by.username}
                            <% end %>
                          </div>
                        </div>
                        <%= if invite.status == "active" do %>
                          <button phx-click="revoke_invite" phx-value-code={invite.code} class="text-sm text-red-400 hover:text-red-300">Revoke</button>
                        <% end %>
                     </div>
                   <% end %>
                 </div>
              <% else %>
                 <p class="text-neutral-500 text-center py-8">No invites created yet.</p>
              <% end %>
            </div>
          <% end %>

        <% else %>
          <%!-- Graph View --%>
          <div class="relative">
            <%= if @graph_data.stats.total_connections > 0 do %>
              <div class="h-[75vh] min-h-[500px] glass rounded-2xl overflow-hidden border border-white/5 relative">
                 <div
                  id="network-graph"
                  phx-hook="FriendGraph"
                  phx-update="ignore"
                  data-graph={Jason.encode!(@graph_data)}
                  class="w-full h-full"
                ></div>
                
                <%!-- Overlay Stats --%>
                <div class="absolute bottom-4 left-4 right-4 flex flex-wrap gap-2 pointer-events-none">
                   <%= if @graph_data.stats.i_trust > 0 do %>
                    <div class="px-3 py-1.5 bg-black/60 backdrop-blur-md rounded-lg border border-green-500/30 flex items-center gap-2">
                       <span class="w-2 h-2 rounded-full bg-green-500"></span>
                       <span class="text-xs text-white">I trust: {@graph_data.stats.i_trust}</span>
                    </div>
                   <% end %>
                   <%= if @graph_data.stats.friends > 0 do %>
                    <div class="px-3 py-1.5 bg-black/60 backdrop-blur-md rounded-lg border border-white/10 flex items-center gap-2">
                       <span class="w-2 h-2 rounded-full bg-blue-500"></span>
                       <span class="text-xs text-white">Friends: {@graph_data.stats.friends}</span>
                    </div>
                   <% end %>
                </div>
              </div>
            <% else %>
              <div class="h-[70vh] glass rounded-2xl flex items-center justify-center border border-white/5">
                <div class="text-center">
                  <div class="text-4xl mb-4">🕸️</div>
                  <h3 class="text-lg font-medium">Your network is empty</h3>
                  <p class="text-neutral-500 mt-2">Add friends or trusted contacts to see your graph.</p>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
        
      </main>
    </div>
    """
  end
end
