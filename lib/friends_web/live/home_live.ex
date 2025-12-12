defmodule FriendsWeb.HomeLive do
  use FriendsWeb, :live_view

  alias Friends.Social
  alias Friends.Social.Presence
  alias Friends.Repo
  import Ecto.Query
  require Logger

  @initial_batch 20
  @colors ~w(#ef4444 #f97316 #eab308 #22c55e #14b8a6 #3b82f6 #8b5cf6 #ec4899)

  def mount(%{"room" => room_code}, session, socket) do
    mount_room(socket, room_code, session)
  end

  def mount(_params, session, socket) do
    # Dashboard / Index
    mount_dashboard(socket, session)
  end

  defp mount_dashboard(socket, session) do
    session_id = generate_session_id()
    
    # Try to get user from session
    {session_user, session_user_id, session_user_color, session_user_name} =
      load_session_user(session)

    if connected?(socket) and session_user do
      # Subscribe to user's personal channel
      Phoenix.PubSub.subscribe(Friends.PubSub, "friends:user:#{session_user.id}")
    end

    socket =
      socket
      |> assign(:session_id, session_id)
      |> assign(:room, nil) # No specific room
      |> assign(:page_title, "Home")
      |> assign(:current_user, session_user)
      |> assign(:user_id, session_user_id)
      |> assign(:user_color, session_user_color)
      |> assign(:user_name, session_user_name)
      |> assign(:auth_status, if(session_user, do: :authed, else: :pending))
      |> assign(:viewers, [])
      |> assign(:show_chat_panel, false)
      |> assign(:show_room_modal, false)
      |> assign(:show_name_modal, false)
      |> assign(:show_note_modal, false)
      |> assign(:show_settings_modal, false)
      |> assign(:show_network_modal, false)
      # Dashboard specific assigns
      |> assign(:user_rooms, if(session_user, do: Social.list_user_rooms(session_user.id), else: []))
      |> assign(:dashboard_tab, "contacts")
      |> assign(:create_group_modal, false)
      |> assign(:new_room_name, "")
      |> assign(:join_code, "")
      |> assign(:current_route, "/")
      |> assign(:show_header_dropdown, false)
      # Required for layout to not crash
      |> assign(:room_access_denied, false)
      |> assign(:feed_mode, "dashboard")

    socket = maybe_bootstrap_identity(socket, get_connect_params(socket))

    {:ok, socket}
  end

  defp load_session_user(session) do
    case session["user_id"] do
      nil -> {nil, nil, nil, nil}
      user_id ->
        case Social.get_user(user_id) do
          nil -> {nil, nil, nil, nil}
          user ->
            color = Enum.at(@colors, rem(user.id, length(@colors)))
            {user, "user-#{user.id}", color, user.display_name || user.username}
        end
    end
  end

  defp mount_room(socket, room_code, session) do
    session_id = generate_session_id()

    room =
      case Social.get_room_by_code(room_code) do
        nil -> 
          # Instead of creating public square, we might direct to home or handle error
          if room_code == "lobby", do: nil, else: nil
        r -> r
      end
    
    # Check if room exists
    if is_nil(room) do
      # If room doesn't exist, we'll redirect in handle_params or render not found
      # For now let's just setup a dummy state that redirects
      {:ok, push_navigate(socket, to: ~p"/")}
    else
      {session_user, session_user_id, session_user_color, session_user_name} =
        load_session_user(session)

      can_access = Social.can_access_room?(room, session_user && session_user.id)

      # Load initial batch only if access is allowed
      {_photos, _notes, items} =
        if can_access do
          photos = Social.list_photos(room.id, @initial_batch, offset: 0)
          notes = Social.list_notes(room.id, @initial_batch, offset: 0)
          {photos, notes, build_items(photos, notes)}
        else
          {[], [], []}
        end

      # Subscribe when connected
      if connected?(socket) and can_access do
        Social.subscribe(room.code)
        Phoenix.PubSub.subscribe(Friends.PubSub, "friends:presence:#{room.code}")
        
        # Subscribe to user-specific events (room creations, etc.)
        if session_user do
          Phoenix.PubSub.subscribe(Friends.PubSub, "friends:user:#{session_user.id}")
        end

        # Request identity from client once socket is connected
        push_event(socket, "request_identity", %{})

        # Regenerate any missing thumbnails in the background so placeholders get filled
        Task.start(fn -> regenerate_all_missing_thumbnails(room.id, room.code) end)
      end

      socket =
        socket
        |> assign(:session_id, session_id)
        |> assign(:room, room)
        |> assign(:page_title, room.name || room.code)
        |> assign(:current_user, session_user)
        |> assign(:user_id, session_user_id)
        |> assign(:user_color, session_user_color)
        |> assign(:user_name, session_user_name)
        |> assign(:room_invite_username, "")
        |> assign(:auth_status, if(session_user, do: :authed, else: :pending))
        |> assign(:browser_id, nil)
        |> assign(:fingerprint, nil)
        |> assign(:viewers, [])
        |> assign(:item_count, length(items))
        |> assign(:no_more_items, if(can_access, do: length(items) < @initial_batch, else: true))
        |> assign(:feed_mode, "room")
        |> assign(:room_tab, "content")  # "content" or "chat"
        |> assign(:room_messages, [])
        |> assign(:new_chat_message, "")
        |> assign(:recording_voice, false)
        |> assign(:show_chat_panel, room.is_private) # Collapsible chat panel, default open for private
        |> assign(:show_room_modal, false)
        |> assign(:show_name_modal, false)
        |> assign(:show_note_modal, false)
        |> assign(:show_settings_modal, false)
        |> assign(:show_network_modal, false)
        |> assign(:settings_tab, "profile")
        |> assign(:network_tab, "friends")
        |> assign(:note_input, "")
        |> assign(:join_code, "")
        |> assign(:new_room_name, "")
        |> assign(:create_private_room, false)
        |> assign(:name_input, "")
        |> assign(:uploading, false)
        |> assign(:invites, [])
        |> assign(:trusted_friends, [])
        |> assign(:outgoing_trust_requests, [])
        |> assign(:pending_requests, if(session_user, do: Social.list_friend_requests(session_user.id), else: []))
        |> assign(:friend_search, "")
        |> assign(:friend_search_results, [])
        |> assign(:recovery_requests, [])
        |> assign(:room_members, [])
        |> assign(:member_invite_search, "")
        |> assign(:member_invite_results, [])
        |> assign(:user_private_rooms, if(session_user, do: Social.list_user_rooms(session_user.id), else: []))
        |> assign(:public_rooms, Social.list_public_rooms())
        |> assign(:show_header_dropdown, false)
        |> assign(:show_invite_modal, false)
        |> assign(:current_route, "/r/#{room.code}")
        |> assign(:network_filter, "trusted")
        |> assign(:room_access_denied, not can_access)
        |> assign(:show_image_modal, false)
        |> assign(:full_image_data, nil)
        |> assign(:photo_order, if(can_access, do: photo_ids(items), else: []))
        |> assign(:current_photo_id, nil)
        |> stream(:items, items, dom_id: &("item-#{&1.unique_id}"))
        |> maybe_allow_upload(can_access)

      socket = maybe_bootstrap_identity(socket, get_connect_params(socket))

      {:ok, socket}
    end
  end

  def handle_params(%{"room" => room_code}, _uri, socket) do
    if socket.assigns.room.code != room_code do
      old_room = socket.assigns.room

      if socket.assigns.user_id do
        Presence.untrack(self(), old_room.code, socket.assigns.user_id)
      end

      Social.unsubscribe(old_room.code)
      Phoenix.PubSub.unsubscribe(Friends.PubSub, "friends:presence:#{old_room.code}")

      room =
        case Social.get_room_by_code(room_code) do
          nil -> Social.get_or_create_public_square()
          r -> r
        end

      can_access = Social.can_access_room?(room, current_user_id(socket))

      if can_access do
        Social.subscribe(room.code)
        Phoenix.PubSub.subscribe(Friends.PubSub, "friends:presence:#{room.code}")

        if socket.assigns.user_id do
          Presence.track_user(
            self(),
            room.code,
            socket.assigns.user_id,
            socket.assigns.user_color,
            socket.assigns.user_name
          )
        end
      end

      {_photos, _notes, items} =
        if can_access do
          photos = Social.list_photos(room.id, @initial_batch, offset: 0)
          notes = Social.list_notes(room.id, @initial_batch, offset: 0)
          {photos, notes, build_items(photos, notes)}
        else
          {[], [], []}
        end

      viewers = if can_access, do: Presence.list_users(room.code), else: []

      # Refresh room lists
      private_rooms = case socket.assigns.current_user do
        nil -> []
        user -> Social.list_user_rooms(user.id)
      end
      public_rooms = Social.list_public_rooms()

      {:noreply,
       socket
       |> assign(:room, room)
       |> assign(:page_title, room.name || room.code)
       |> assign(:item_count, length(items))
       |> assign(:no_more_items, if(can_access, do: length(items) < @initial_batch, else: true))
       |> assign(:viewers, viewers)
       |> assign(:room_access_denied, not can_access)
       |> assign(:photo_order, if(can_access, do: photo_ids(items), else: []))
       |> assign(:user_private_rooms, private_rooms)
       |> assign(:public_rooms, public_rooms)
       |> stream(:items, items, reset: true, dom_id: &("item-#{&1.unique_id}"))}


    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle_user_dropdown", _params, socket) do
    {:noreply, assign(socket, :show_user_dropdown, !socket.assigns.show_user_dropdown)}
  end

  def handle_event("close_user_dropdown", _params, socket) do
    {:noreply, assign(socket, :show_user_dropdown, false)}
  end

  def handle_params(_params, _uri, socket) when socket.assigns.live_action == :index do
    # When navigating to dashboard, ensure we clean up room subscriptions if coming from a room
    if socket.assigns[:room] do
       old_room = socket.assigns.room
       Social.unsubscribe(old_room.code)
       Phoenix.PubSub.unsubscribe(Friends.PubSub, "friends:presence:#{old_room.code}")
       if socket.assigns.user_id do
         Presence.untrack(self(), old_room.code, socket.assigns.user_id)
       end
    end
    
    # Refresh user rooms
    user_rooms = if socket.assigns.current_user do
       Social.list_user_dashboard_rooms(socket.assigns.current_user.id)
    else
       []
    end

    {:noreply, 
     socket 
     |> assign(:room, nil)  
     |> assign(:page_title, "Home")
     |> assign(:user_rooms, user_rooms)
     |> assign(:feed_mode, "dashboard")
     |> assign(:current_route, "/")
    }
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-neutral-950 text-neutral-200 font-sans selection:bg-neutral-700 selection:text-white pb-20">
      <%= if @live_action == :index do %>
        <%!-- Dashboard View --%>
        <div class="max-w-[1600px] mx-auto p-4 sm:p-8">
           <%= if @current_user do %>
             <div class="grid grid-cols-1 md:grid-cols-2 gap-8">
               
               <%!-- Contacts (Direct Messages) --%>
               <div class="space-y-4">
                 <div class="flex items-center justify-between">
                   <h2 class="text-xl font-medium text-white flex items-center gap-2">
                     <span>💬</span> Contacts
                   </h2>
                   <.link navigate={~p"/network"} class="text-sm text-neutral-500 hover:text-white transition-colors">
                     Manage Contacts
                   </.link>
                 </div>
                 
                 <div class="space-y-2">
                   <% dm_rooms = Enum.filter(@user_rooms, & &1.room_type == "dm") %>
                   <%= if dm_rooms == [] do %>
                     <div class="p-8 rounded-2xl glass border border-white/5 text-center">
                       <p class="text-neutral-500 mb-2">No conversations yet</p>
                       <.link navigate={~p"/network"} class="text-emerald-400 hover:text-emerald-300 text-sm">
                         Start a chat from Network
                       </.link>
                     </div>
                   <% else %>
                     <%= for room <- dm_rooms do %>
                       <.link navigate={~p"/r/#{room.code}"} class="block group">
                         <div class="p-4 rounded-2xl glass border border-white/5 hover:border-emerald-500/30 hover:bg-white/5 transition-all flex items-center gap-4">
                           <div class="w-12 h-12 rounded-full bg-emerald-500/10 flex items-center justify-center text-emerald-400 text-xl group-hover:scale-110 transition-transform">
                             💬
                           </div>
                           <div class="flex-1 min-w-0">
                             <div class="font-medium text-neutral-200 group-hover:text-white truncate">
                               {room.name || room.code}
                             </div>
                             <div class="text-xs text-neutral-500 truncate">
                               Click to chat
                             </div>
                           </div>
                           <div class="text-neutral-600 group-hover:text-neutral-400 transition-colors">
                             →
                           </div>
                         </div>
                       </.link>
                     <% end %>
                   <% end %>
                 </div>
               </div>

               <%!-- Groups --%>
               <div class="space-y-4">
                 <div class="flex items-center justify-between">
                   <h2 class="text-xl font-medium text-white flex items-center gap-2">
                     <span>👥</span> Groups
                   </h2>
                   <button phx-click="open_create_group_modal" class="text-sm text-emerald-400 hover:text-emerald-300 transition-colors flex items-center gap-1 cursor-pointer">
                     <span>+</span> Create Group
                   </button>
                 </div>
                 
                 <div class="space-y-2">
                   <% group_rooms = Enum.filter(@user_rooms, & &1.room_type != "dm") %>
                   <%= if group_rooms == [] do %>
                     <div class="p-8 rounded-2xl glass border border-white/5 text-center">
                       <p class="text-neutral-500 mb-2">No groups yet</p>
                       <button phx-click="open_create_group_modal" class="text-emerald-400 hover:text-emerald-300 text-sm cursor-pointer">
                         Create your first group
                       </button>
                     </div>
                   <% else %>
                     <%= for room <- group_rooms do %>
                       <.link navigate={~p"/r/#{room.code}"} class="block group">
                         <div class="p-4 rounded-2xl glass border border-white/5 hover:border-blue-500/30 hover:bg-white/5 transition-all flex items-center gap-4">
                           <div class="w-12 h-12 rounded-full bg-blue-500/10 flex items-center justify-center text-blue-400 text-xl group-hover:scale-110 transition-transform">
                             👥
                           </div>
                           <div class="flex-1 min-w-0">
                             <div class="font-medium text-neutral-200 group-hover:text-white truncate">
                               {room.name || room.code}
                             </div>
                             <div class="text-xs text-neutral-500 truncate">
                               Private Group
                             </div>
                           </div>
                           <div class="text-neutral-600 group-hover:text-neutral-400 transition-colors">
                             →
                           </div>
                         </div>
                       </.link>
                     <% end %>
                   <% end %>
                 </div>
               </div>

             </div>
           <% else %>
             <%!-- Guests Landing --%>
             <div class="max-w-md mx-auto mt-20 text-center">
               <h1 class="text-4xl md:text-5xl font-bold mb-4 bg-clip-text text-transparent bg-gradient-to-br from-white to-neutral-500">
                 Friends
               </h1>
               <p class="text-neutral-400 text-lg mb-8">
                 Simple, secure, and private messaging.
               </p>
               <div class="flex flex-col gap-3">
                 <a href="/login" class="w-full py-3 rounded-xl glass border border-white/10 hover:bg-white/10 transition-colors text-white font-medium">
                   Login
                 </a>
                 <a href="/register" class="w-full py-3 rounded-xl btn-opal text-black font-medium">
                   Create Account
                 </a>
               </div>
             </div>
           <% end %>
        </div>
      <% else %>
        <%!-- Room View --%>
        <div id="friends-app" class="min-h-screen text-white relative" phx-hook="FriendsApp" phx-window-keydown="handle_keydown">
        <%!-- Main content - wider and more spacious --%>
        <div class="max-w-[1600px] mx-auto px-8 py-10">
          <%!-- Feed View Pills --%>
          <% room_label = if @room.code == "lobby", do: "Public Square", else: (@room.name || @room.code) %>
          
          <%= if @current_user do %>
            <div class="flex items-center justify-between mb-6">
              <div class="flex items-center gap-1 p-1 bg-neutral-900/80 border border-white/5 rounded-full backdrop-blur-md">
                <button
                  type="button"
                  phx-click="set_feed_view"
                  phx-value-view="room"
                  class={"px-4 py-1.5 text-sm font-medium rounded-full transition-all flex items-center gap-2 cursor-pointer #{if @feed_mode == "room", do: "bg-neutral-800 text-white shadow-sm ring-1 ring-white/10", else: "text-neutral-500 hover:text-neutral-300"}"}
                >
                  <span>📍</span>
                  <span>{room_label}</span>
                </button>
                <button
                  type="button"
                  phx-click="set_feed_view"
                  phx-value-view="friends"
                  class={"px-4 py-1.5 text-sm font-medium rounded-full transition-all flex items-center gap-2 cursor-pointer #{if @feed_mode == "friends" && @network_filter != "me", do: "bg-neutral-800 text-white shadow-sm ring-1 ring-white/10", else: "text-neutral-500 hover:text-neutral-300"}"}
                >
                  <span>👥</span>
                  <span>Contacts</span>
                </button>
                <button
                  type="button"
                  phx-click="set_feed_view"
                  phx-value-view="me"
                  class={"px-4 py-1.5 text-sm font-medium rounded-full transition-all flex items-center gap-2 cursor-pointer #{if @feed_mode == "friends" && @network_filter == "me", do: "bg-neutral-800 text-white shadow-sm ring-1 ring-white/10", else: "text-neutral-500 hover:text-neutral-300"}"}
                >
                  <span>👤</span>
                  <span>Me</span>
                </button>
              </div>
              
              <%!-- Right-side actions --%>
              <div class="flex items-center gap-3">
                <%!-- Chat toggle for private spaces --%>
                <%= if @room.is_private and @feed_mode == "room" do %>
                  <button
                    type="button"
                    phx-click="toggle_chat_panel"
                    class={"px-3 py-1.5 text-sm font-medium rounded-full transition-all flex items-center gap-2 cursor-pointer #{if @show_chat_panel, do: "bg-emerald-600 text-white", else: "bg-neutral-800/50 text-neutral-400 hover:text-white"}"}
                  >
                    <span>💬</span>
                    <span class="hidden sm:inline"><%= if @show_chat_panel, do: "Hide Chat", else: "Show Chat" %></span>
                  </button>
                <% end %>
                <%!-- Invite button --%>
                <%= if @room.code != "lobby" and @feed_mode == "room" do %>
                  <button phx-click="open_invite_modal" class="text-sm text-emerald-400 hover:text-emerald-300 flex items-center gap-2 cursor-pointer bg-emerald-500/10 px-3 py-1.5 rounded-lg border border-emerald-500/20">
                    <span>💌</span> <span class="hidden sm:inline">Invite</span>
                  </button>
                <% end %>
              </div>
            </div>
          <% else %>
            <%!-- Spacing for non-logged-in users --%>
            <div class="mb-6"></div>
          <% end %>

          <%!-- Network Info (when in network mode) --%>
          <%= if @feed_mode == "friends" && @current_user do %>
            <div class="mb-10 p-6 glass rounded-2xl border border-white/5 opal-glow-subtle">
              <div class="flex items-center justify-between mb-3">
                <div class="text-xs text-neutral-500">your trust network</div>
                <button
                  type="button"
                  phx-click="open_network_modal"
                  class="text-xs text-green-500 hover:text-green-400 cursor-pointer"
                >
                  manage →
                </button>
              </div>
              <%= if @trusted_friends != [] do %>
                <div class="flex flex-wrap gap-2">
                  <%= for friend <- Enum.take(@trusted_friends, 10) do %>
                    <div class="flex items-center gap-2 px-2 py-1 bg-neutral-800 rounded-full">
                      <div
                        class="w-2 h-2 rounded-full"
                        style={"background-color: #{trusted_user_color(friend.trusted_user)}"}
                      />
                      <span class="text-xs text-neutral-300">@{friend.trusted_user.username}</span>
                    </div>
                  <% end %>
                  <%= if length(@trusted_friends) > 10 do %>
                    <div class="px-2 py-1 text-xs text-neutral-500">
                      +{length(@trusted_friends) - 10} more
                    </div>
                  <% end %>
                </div>
                <div class="mt-3 text-xs text-neutral-600">
                  showing activity from {length(@trusted_friends)} trusted connection<%= if length(@trusted_friends) != 1, do: "s" %>
                </div>
              <% else %>
                <%= if @outgoing_trust_requests != [] do %>
                  <div class="space-y-2">
                    <div class="text-sm text-neutral-400">waiting for confirmation...</div>
                    <div class="flex flex-wrap gap-2">
                      <%= for req <- Enum.take(@outgoing_trust_requests, 10) do %>
                        <div class="flex items-center gap-2 px-2 py-1 bg-neutral-800 rounded-full">
                          <div
                            class="w-2 h-2 rounded-full"
                            style={"background-color: #{trusted_user_color(req.trusted_user)}"}
                          />
                          <span class="text-xs text-neutral-300">@{req.trusted_user.username}</span>
                        </div>
                      <% end %>
                    </div>
                    <div class="text-xs text-neutral-600">
                      they'll appear here after they confirm
                    </div>
                  </div>
                <% else %>
                  <div class="flex items-center gap-3 p-4 bg-neutral-900/50 border border-neutral-800 rounded-lg">
                    <div class="text-neutral-600">
                      <svg class="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z"></path>
                      </svg>
                    </div>
                    <div class="flex-1">
                      <p class="text-sm text-neutral-500 font-medium">no trusted connections yet</p>
                      <p class="text-xs text-neutral-600 mt-0.5">add friends in settings to see their activity</p>
                    </div>
                  </div>
                <% end %>
              <% end %>
            </div>
          <% end %>

          <%!-- Main split-view layout container --%>
          <div class={if @room.is_private and @feed_mode == "room" and not @room_access_denied and @show_chat_panel, do: "flex gap-6", else: ""}>
            <%!-- Left: Main content area (narrows when chat visible) --%>
            <div class={if @room.is_private and @feed_mode == "room" and not @room_access_denied and @show_chat_panel, do: "flex-1 min-w-0", else: ""}>



          <%!-- Upload progress --%>
          <%= for entry <- @uploads.photo.entries do %>
            <div class="mb-4 bg-neutral-900 p-3">
              <div class="flex items-center gap-3">
                <div class="flex-1 bg-neutral-800 h-1">
                  <div class="bg-white h-full transition-all" style={"width: #{entry.progress}%"} />
                </div>
                <span class="text-xs text-neutral-500">{entry.progress}%</span>
                <button type="button" phx-click="cancel_upload" phx-value-ref={entry.ref} class="text-neutral-500 hover:text-white text-xs cursor-pointer">
                  cancel
                </button>
              </div>
            </div>
          <% end %>

          <%!-- Access Denied for Private Rooms --%>
          <%= if @room_access_denied do %>
            <div class="text-center py-20">
              <p class="text-4xl mb-4">🔒</p>
              <p class="text-neutral-400 text-sm font-medium">private room</p>
              <p class="text-neutral-600 text-xs mt-2">you don't have access to this room</p>
              <%= if is_nil(@current_user) do %>
                <a href={"/register?join=#{@room.code}"} class="inline-block mt-4 px-4 py-2 bg-emerald-500 text-black text-sm font-medium rounded-lg hover:bg-emerald-400 transition-colors">
                  register to join
                </a>
                <p class="text-neutral-600 text-xs mt-2">or <a href="/login" class="text-emerald-400 hover:text-emerald-300">login</a> if you have an account</p>
              <% else %>
                <p class="text-neutral-700 text-xs mt-4">ask the owner to invite you</p>
              <% end %>
            </div>
          <% else %>
            <%!-- Content grid --%>
            <%= if @item_count == 0 and (is_nil(@current_user) or @room_access_denied) do %>
              <div class="text-center py-20">
                <%= if @feed_mode == "friends" do %>
                  <%= if @network_filter == "me" do %>
                    <div class="mb-4 opacity-40">
                      <svg class="w-16 h-16 mx-auto text-neutral-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z"></path>
                      </svg>
                    </div>
                    <p class="text-neutral-500 text-base font-medium mb-2">you haven't posted yet</p>
                    <p class="text-neutral-600 text-sm">share a photo or note to see it here</p>
                  <% else %>
                    <div class="mb-4 opacity-40">
                      <svg class="w-16 h-16 mx-auto text-neutral-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z"></path>
                      </svg>
                    </div>
                    <p class="text-neutral-500 text-base font-medium mb-2">no activity from your network</p>
                    <p class="text-neutral-600 text-sm">add trusted connections to see their photos and notes</p>
                  <% end %>
                <% else %>
                  <div class="mb-4 opacity-40">
                    <svg class="w-16 h-16 mx-auto text-neutral-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M20 13V6a2 2 0 00-2-2H6a2 2 0 00-2 2v7m16 0v5a2 2 0 01-2 2H6a2 2 0 01-2-2v-5m16 0h-2.586a1 1 0 00-.707.293l-2.414 2.414a1 1 0 01-.707.293h-3.172a1 1 0 01-.707-.293l-2.414-2.414A1 1 0 006.586 13H4"></path>
                    </svg>
                  </div>
                  <p class="text-neutral-500 text-base font-medium mb-2">this space is empty</p>
                  <p class="text-neutral-600 text-sm">share a photo or note to get started</p>
                <% end %>
              </div>
            <% else %>
            <div
              id="items-grid"
              phx-update="stream"
              phx-hook="PhotoGrid"
              class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 2xl:grid-cols-6 gap-4"
            >
              <%!-- Add Photo Card --%>
              <%= if @current_user and not @room_access_denied do %>
                <form id="upload-form" phx-change="validate" phx-submit="save" class="contents">
                  <label
                    for={@uploads.photo.ref}
                    class="group relative aspect-square glass rounded-xl border border-white/5 hover:border-white/20 cursor-pointer flex flex-col items-center justify-center gap-2 transition-all hover:bg-white/5"
                  >
                     <div class="w-10 h-10 rounded-full bg-white/5 flex items-center justify-center text-xl group-hover:scale-110 transition-transform">📷</div>
                     <span class="text-sm text-neutral-400 group-hover:text-white"><%= if @uploading, do: "Uploading...", else: "Add Photo" %></span>
                     <.live_file_input upload={@uploads.photo} class="sr-only" />
                  </label>
                </form>

                <%!-- Add Note Card --%>
                <button
                  type="button"
                  phx-click="open_note_modal"
                  class="group relative aspect-square glass rounded-xl border border-white/5 hover:border-white/20 cursor-pointer flex flex-col items-center justify-center gap-2 transition-all hover:bg-white/5"
                >
                   <div class="w-10 h-10 rounded-full bg-white/5 flex items-center justify-center text-xl group-hover:scale-110 transition-transform">📝</div>
                   <span class="text-sm text-neutral-400 group-hover:text-white">Add Note</span>
                </button>
              <% end %>


              <%= for {dom_id, item} <- @streams.items do %>
                <%= if Map.get(item, :type) == :photo do %>
                  <div id={dom_id} class="photo-item group relative aspect-square glass overflow-hidden rounded-xl border border-white/5 hover:border-white/15 cursor-pointer" phx-click="view_full_image" phx-value-photo_id={item.id}>
                    <%= if item.thumbnail_data do %>
                      <img
                        src={item.thumbnail_data}
                        alt=""
                        class="w-full h-full object-cover loaded"
                        decoding="async"
                      />
                    <% else %>
                      <div class="w-full h-full flex items-center justify-center bg-neutral-800 skeleton border-2 border-dashed border-neutral-600">
                        <div class="text-center">
                          <svg class="w-8 h-8 mx-auto mb-2 text-neutral-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"></path>
                          </svg>
                          <span class="text-neutral-400 text-xs">loading</span>
                        </div>
                      </div>
                    <% end %>

                    <%!-- Overlay on hover --%>
                    <div class="absolute inset-0 bg-black/60 opacity-0 group-hover:opacity-100 transition-opacity flex flex-col justify-end p-3">
                      <div class="flex items-center gap-2 text-xs">
                        <div
                          class="w-2 h-2 rounded-full"
                          style={"background-color: #{item.user_color}"}
                        />
                        <span class="text-neutral-300">
                          {item.user_name || String.slice(item.user_id, 0, 6)}
                        </span>
                        <span class="text-neutral-600">{format_time(item.uploaded_at)}</span>
                      </div>
                      <%= if item.description do %>
                        <p class="text-neutral-400 text-xs mt-1 line-clamp-2">{item.description}</p>
                      <% end %>
                      <%= if item.user_id == @user_id do %>
                        <button
                          type="button"
                          phx-click="delete_photo"
                          phx-value-id={item.id}
                          data-confirm="delete?"
                          class="absolute top-2 right-2 text-neutral-500 hover:text-red-500 text-xs cursor-pointer"
                        >
                          delete
                        </button>
                      <% end %>
                    </div>
                  </div>
                <% else %>
                  <%!-- Note card --%>
                  <div id={dom_id} class="group relative bg-neutral-900 p-4 min-h-[120px] flex flex-col rounded-lg border border-neutral-800/80 shadow-md shadow-black/30 hover:border-neutral-700 transition">
                    <p class="text-sm text-neutral-300 flex-1 line-clamp-4">{item.content}</p>
                    <div class="flex items-center gap-2 text-xs mt-3 pt-3 border-t border-neutral-800">
                      <div
                        class="w-2 h-2 rounded-full"
                        style={"background-color: #{item.user_color}"}
                      />
                      <span class="text-neutral-500">
                        {item.user_name || String.slice(item.user_id, 0, 6)}
                      </span>
                      <span class="text-neutral-700">{format_time(item.inserted_at)}</span>
                    </div>
                    <%= if item.user_id == @user_id do %>
                      <button
                        type="button"
                        phx-click="delete_note"
                        phx-value-id={item.id}
                        data-confirm="delete?"
                        class="absolute top-2 right-2 opacity-0 group-hover:opacity-100 text-neutral-600 hover:text-red-500 text-xs transition-opacity cursor-pointer"
                      >
                        delete
                      </button>
                    <% end %>
                  </div>
                <% end %>
              <% end %>
            </div>
            <%= unless @no_more_items do %>
              <div class="flex justify-center mt-6">
                <button
                  type="button"
                  phx-click="load_more"
                  phx-disable-with="loading..."
                  class="px-4 py-2 text-sm border border-neutral-700 text-neutral-300 hover:border-neutral-500 hover:text-white transition-colors cursor-pointer min-w-[140px]"
                >
                  show more
                </button>
              </div>
            <% end %>
            <% end %>
          <% end %>

            </div><%!-- Close left content wrapper --%>

            <%!-- Right: Chat Panel (collapsible, only shown for private spaces) --%>
            <%= if @room.is_private and @feed_mode == "room" and not @room_access_denied and @show_chat_panel and @current_user do %>
              <div class="hidden lg:block w-2/5 min-w-[320px] max-w-[500px]">
                <div class="glass rounded-2xl border border-white/10 overflow-hidden sticky top-24" style="height: calc(100vh - 180px);">
                  <%!-- Chat Header --%>
                  <div class="p-3 border-b border-white/10 flex items-center justify-between">
                    <div class="flex items-center gap-2">
                      <span class="text-emerald-400">💬</span>
                      <span class="font-medium text-sm">Chat</span>
                      <span class="text-[10px] text-emerald-400 flex items-center gap-1">
                        <span class="w-1.5 h-1.5 rounded-full bg-emerald-400"></span>
                        E2E
                      </span>
                    </div>
                    <button
                      type="button"
                      phx-click="toggle_chat_panel"
                      class="text-neutral-400 hover:text-white cursor-pointer text-sm"
                    >
                      ✕
                    </button>
                  </div>

                  <%!-- Messages --%>
                  <div id="room-messages-container" class="overflow-y-auto p-3 space-y-3" style="height: calc(100% - 120px);" phx-hook="RoomChatScroll" data-room-id={@room.id}>
                    <%= if @room_messages == [] do %>
                      <div class="flex items-center justify-center h-full text-neutral-500">
                        <div class="text-center">
                          <p class="text-3xl mb-2">💬</p>
                          <p class="text-sm">No messages yet</p>
                        </div>
                      </div>
                    <% else %>
                      <%= for message <- @room_messages do %>
                        <div class={"flex #{if message.sender_id == @current_user.id, do: "justify-end", else: "justify-start"}"}>
                          <div class={"max-w-[85%] rounded-xl px-3 py-2 #{if message.sender_id == @current_user.id, do: "bg-emerald-600", else: "bg-neutral-800"}"}>
                            <%= if message.sender_id != @current_user.id do %>
                              <p class="text-[10px] text-neutral-400 mb-0.5">@{message.sender.username}</p>
                            <% end %>
                            <%= if message.content_type == "voice" do %>
                              <div class="flex items-center gap-2" id={"room-voice-#{message.id}"} phx-hook="RoomVoicePlayer" data-message-id={message.id} data-room-id={@room.id}>
                                <button class="w-6 h-6 rounded-full bg-white/20 flex items-center justify-center hover:bg-white/30 transition-colors cursor-pointer room-voice-play-btn text-xs">
                                  ▶
                                </button>
                                <div class="flex-1 h-1 bg-white/20 rounded-full min-w-[60px]">
                                  <div class="room-voice-progress h-full bg-white rounded-full" style="width: 0%"></div>
                                </div>
                                <span class="text-[10px] text-white/70">{format_voice_duration(message.metadata["duration_ms"])}</span>
                                <span class="hidden" id={"room-msg-#{message.id}"} data-encrypted={Base.encode64(message.encrypted_content)} data-nonce={Base.encode64(message.nonce)}></span>
                              </div>
                            <% else %>
                              <p class="text-sm room-decrypted-content" id={"room-msg-#{message.id}"} data-encrypted={Base.encode64(message.encrypted_content)} data-nonce={Base.encode64(message.nonce)}>
                                <span class="text-neutral-400 italic text-xs">Decrypting...</span>
                              </p>
                            <% end %>
                            <p class="text-[9px] text-white/50 mt-1">{Calendar.strftime(message.inserted_at, "%H:%M")}</p>
                          </div>
                        </div>
                      <% end %>
                    <% end %>
                  </div>

                  <%!-- Message Input --%>
                  <div class="p-3 border-t border-white/10">
                    <div id="room-message-input-area" class="flex items-center gap-2" phx-hook="RoomChatEncryption" data-room-id={@room.id}>
                      <button
                        type="button"
                        phx-click={if @recording_voice, do: "stop_room_recording", else: "start_room_recording"}
                        class={"w-8 h-8 rounded-full flex items-center justify-center transition-colors cursor-pointer text-sm #{if @recording_voice, do: "bg-red-500 animate-pulse", else: "bg-white/10 hover:bg-white/20"}"}
                        id="room-voice-btn"
                      >
                        🎤
                      </button>
                      <input
                        type="text"
                        value={@new_chat_message}
                        phx-keyup="update_chat_message"
                        placeholder="Message..."
                        class="flex-1 bg-neutral-900 border border-white/10 rounded-full px-3 py-1.5 text-sm focus:outline-none focus:border-white/30"
                        id="room-message-input"
                        autocomplete="off"
                      />
                      <button
                        id="send-room-message-btn"
                        class="w-8 h-8 rounded-full bg-emerald-600 hover:bg-emerald-500 flex items-center justify-center transition-colors cursor-pointer text-sm"
                      >
                        ➤
                      </button>
                    </div>
                  </div>
                </div>
              </div>
            <% end %>
          </div><%!-- Close flex container --%>
        </div>

        <%!-- Room Modal --%>
        <%= if @show_room_modal do %>
          <div id="room-modal-overlay" class="fixed inset-0 z-50 flex items-end sm:items-center justify-center modal-backdrop" phx-click-away="close_room_modal" role="dialog" aria-modal="true" aria-labelledby="room-modal-title" phx-hook="LockScroll">
            <div class="w-full sm:max-w-md sm:mx-4 bg-neutral-900 sm:rounded-2xl rounded-t-2xl border-t sm:border border-neutral-800 shadow-2xl max-h-[85vh] flex flex-col">
              <%!-- Header --%>
              <div class="flex items-center justify-between p-4 border-b border-neutral-800 shrink-0">
                <h2 id="room-modal-title" class="text-lg font-semibold text-white">Groups</h2>
                <button type="button" phx-click="close_room_modal" class="w-10 h-10 flex items-center justify-center text-neutral-400 hover:text-white hover:bg-neutral-800 rounded-full transition-all cursor-pointer" aria-label="Close">
                  <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                  </svg>
                </button>
              </div>

              <%!-- Content - scrollable --%>
              <div class="flex-1 overflow-y-auto p-4 space-y-4">


                <%= if @room.is_private && @current_user do %>
                  <div class="p-4 bg-neutral-800/50 rounded-xl space-y-3">
                    <div class="text-xs text-neutral-500 uppercase tracking-wider">Invite people</div>
                    <p class="text-sm text-neutral-300">Share this code or link so trusted people can join your private space.</p>
                    <div class="space-y-2">
                      <div class="flex gap-2">
                        <input
                          type="text"
                          value={@room.code}
                          readonly
                          class="flex-1 px-3 py-2 bg-neutral-900 border border-neutral-800 rounded-lg text-sm text-white font-mono cursor-text select-all"
                        />
                        <button
                          id="copy-room-code"
                          type="button"
                          phx-hook="CopyToClipboard"
                          data-copy={@room.code}
                          class="px-3 py-2 bg-neutral-200 text-black text-sm rounded-lg hover:bg-white transition-colors cursor-pointer"
                        >
                          Copy code
                        </button>
                      </div>
                      <div class="flex gap-2">
                        <input
                          type="text"
                          value={url(~p"/r/#{@room.code}")}
                          readonly
                          class="flex-1 px-3 py-2 bg-neutral-900 border border-neutral-800 rounded-lg text-sm text-white font-mono cursor-text select-all"
                        />
                        <button
                          id="copy-room-link"
                          type="button"
                          phx-hook="CopyToClipboard"
                          data-copy={url(~p"/r/#{@room.code}")}
                          class="px-3 py-2 bg-neutral-200 text-black text-sm rounded-lg hover:bg-white transition-colors cursor-pointer"
                        >
                          Copy link
                        </button>
                      </div>
                    </div>
                    <p class="text-xs text-neutral-500">Only members can access private spaces. Share wisely.</p>

                    <%= if @room.owner_id == @current_user.id do %>
                      <div class="pt-2 space-y-2">
                        <div class="text-xs text-neutral-500 uppercase tracking-wider">Add member by username</div>
                        <form phx-submit="add_room_member" phx-change="update_room_invite_username" class="flex gap-2">
                          <input
                            type="text"
                            name="username"
                            value={@room_invite_username}
                            placeholder="friend_username"
                            class="flex-1 px-3 py-2 bg-neutral-900 border border-neutral-800 rounded-lg text-sm text-white placeholder:text-neutral-700 focus:outline-none focus:border-neutral-600"
                          />
                          <button
                            type="submit"
                            class="px-3 py-2 bg-white text-black text-sm rounded-lg hover:bg-neutral-200 transition-colors cursor-pointer"
                            phx-disable-with="adding..."
                          >
                            Add
                          </button>
                        </form>
                      </div>
                    <% end %>
                  </div>
                <% end %>



                <%!-- Private Rooms --%>
                <%= if @current_user && @user_private_rooms != [] do %>
                  <div>
                    <div class="flex items-center gap-2 mb-3">
                      <span class="text-xs text-neutral-500 uppercase tracking-wider">Your Private Spaces</span>
                      <div class="flex-1 border-t border-neutral-800"></div>
                    </div>
                    <div class="space-y-2">
                      <%= for room <- @user_private_rooms do %>
                        <button
                          type="button"
                          phx-click="switch_room"
                          phx-value-code={room.code}
                          class={[
                            "w-full p-3 rounded-xl text-left transition-all flex items-center gap-3 cursor-pointer",
                            room.code == @room.code && "bg-green-500/20 border border-green-500/30 ring-1 ring-green-500/20",
                            room.code != @room.code && "bg-neutral-800/50 hover:bg-neutral-800 border border-transparent"
                          ]}
                        >
                          <div class="w-8 h-8 bg-green-500/20 rounded-lg flex items-center justify-center">
                            <span class="text-sm">🔒</span>
                          </div>
                          <span class={[
                            "font-medium truncate",
                            room.code == @room.code && "text-green-400",
                            room.code != @room.code && "text-neutral-300"
                          ]}>{room.name || room.code}</span>
                          <%= if room.code == @room.code do %>
                            <span class="ml-auto text-xs text-green-500">✓</span>
                          <% end %>
                        </button>
                      <% end %>
                    </div>
                  </div>
                <% end %>


              </div>

              <%!-- Actions - sticky footer --%>
              <div class="p-4 border-t border-neutral-800 bg-neutral-900 shrink-0 space-y-3">
                <%!-- Join by code --%>
                <form phx-submit="join_room" class="flex gap-2">
                  <input
                    type="text"
                    name="code"
                    value={@join_code}
                    phx-change="update_join_code"
                    placeholder="Enter room code..."
                    class="flex-1 px-4 py-3 bg-neutral-800 border border-neutral-700 rounded-xl text-sm text-white placeholder:text-neutral-500 focus:outline-none focus:border-neutral-500 focus:ring-1 focus:ring-neutral-500"
                  />
                  <button type="submit" phx-disable-with="..." class="w-24 px-5 py-3 bg-white text-black text-sm font-medium rounded-xl hover:bg-neutral-200 transition-colors disabled:opacity-50 cursor-pointer">
                    Join
                  </button>
                </form>

                <%!-- Create new --%>
                <form phx-submit="create_room" phx-change="update_room_form" class="space-y-2">
                  <div class="flex gap-2">
                    <input type="hidden" name="is_private" value="on" />
                    <input
                      type="text"
                      name="name"
                      value={@new_room_name}
                      placeholder="Create a new private group..."
                      class="flex-1 px-4 py-3 bg-neutral-800 border border-neutral-700 rounded-xl text-sm text-white placeholder:text-neutral-500 focus:outline-none focus:border-neutral-500 focus:ring-1 focus:ring-neutral-500"
                    />
                    <button type="submit" phx-disable-with="..." class="w-24 px-5 py-3 border border-neutral-600 text-neutral-300 text-sm font-medium rounded-xl hover:border-neutral-500 hover:text-white hover:bg-neutral-800 transition-all disabled:opacity-50 cursor-pointer">
                      Create
                    </button>
                  </div>
                </form>
              </div>
            </div>
          </div>
        <% end %>

        <%!-- Create Group Modal - Beautiful focused modal --%>
        <%= if @create_group_modal do %>
          <div 
            id="create-group-modal-overlay" 
            class="fixed inset-0 z-50 flex items-center justify-center p-4 modal-backdrop animate-in fade-in duration-200" 
            phx-click-away="close_create_group_modal" 
            role="dialog" 
            aria-modal="true" 
            aria-labelledby="create-group-modal-title"
            phx-hook="LockScroll"
          >
            <div class="w-full max-w-md bg-neutral-900 rounded-2xl border border-neutral-800 shadow-2xl overflow-hidden animate-in zoom-in-95 duration-200">
              <%!-- Header with gradient accent --%>
              <div class="p-6 border-b border-neutral-800 bg-gradient-to-r from-emerald-500/10 to-blue-500/10">
                <div class="flex items-center justify-between">
                  <div>
                    <h2 id="create-group-modal-title" class="text-xl font-semibold text-white">Create Group</h2>
                    <p class="text-sm text-neutral-400 mt-1">Start a private space for your friends</p>
                  </div>
                  <button 
                    type="button" 
                    phx-click="close_create_group_modal" 
                    class="w-10 h-10 flex items-center justify-center text-neutral-400 hover:text-white hover:bg-white/10 rounded-xl transition-all cursor-pointer"
                    aria-label="Close"
                  >
                    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                    </svg>
                  </button>
                </div>
              </div>
              
              <%!-- Form --%>
              <form phx-submit="create_group" phx-change="update_room_form" class="p-6 space-y-6">
                <div>
                  <label for="group-name" class="block text-sm font-medium text-neutral-300 mb-2">
                    Group name <span class="text-neutral-600">(optional)</span>
                  </label>
                  <input
                    type="text"
                    id="group-name"
                    name="name"
                    value={@new_room_name}
                    placeholder="e.g. Weekend Plans, Study Group..."
                    maxlength="50"
                    autofocus
                    class="w-full px-4 py-3 bg-neutral-950 border border-neutral-800 rounded-xl text-white placeholder:text-neutral-600 focus:outline-none focus:border-emerald-500/50 focus:ring-2 focus:ring-emerald-500/20 transition-all"
                  />
                  <p class="text-xs text-neutral-600 mt-2">Leave empty for an auto-generated code name</p>
                </div>
                
                <div class="flex gap-3">
                  <button
                    type="button"
                    phx-click="close_create_group_modal"
                    class="flex-1 px-4 py-3 border border-neutral-700 text-neutral-300 rounded-xl hover:bg-neutral-800 hover:text-white transition-all cursor-pointer"
                  >
                    Cancel
                  </button>
                  <button
                    type="submit"
                    phx-disable-with="Creating..."
                    class="flex-1 px-4 py-3 bg-gradient-to-r from-emerald-500 to-emerald-600 text-white font-medium rounded-xl hover:from-emerald-400 hover:to-emerald-500 transition-all cursor-pointer shadow-lg shadow-emerald-500/25"
                  >
                    Create Group
                  </button>
                </div>
              </form>
              
              <%!-- Info footer --%>
              <div class="px-6 pb-6">
                <div class="p-4 bg-neutral-950/50 border border-neutral-800/50 rounded-xl">
                  <div class="flex items-start gap-3">
                    <span class="text-lg">🔒</span>
                    <div class="text-xs text-neutral-500">
                      <p class="font-medium text-neutral-400 mb-1">Private by default</p>
                      <p>Only people you invite can access your group. Share the link or add members directly.</p>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        <% end %>

        <%= if @show_invite_modal do %>
          <div class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80" phx-click-away="close_invite_modal">
            <div class="w-full max-w-sm bg-neutral-900 border border-neutral-800 rounded-2xl p-6 shadow-2xl space-y-6">
              <div class="flex items-center justify-between">
                <h2 class="text-lg font-semibold text-white">Invite to Space</h2>
                <button type="button" phx-click="close_invite_modal" class="text-neutral-500 hover:text-white cursor-pointer">×</button>
              </div>

              <%= if @room.is_private do %>
                <div class="space-y-2">
                  <div class="text-xs text-neutral-500 uppercase tracking-wider">Share Link</div>
                  <div class="flex gap-2">
                    <input type="text" value={url(~p"/r/#{@room.code}")} readonly class="flex-1 px-3 py-2 bg-neutral-950 border border-neutral-800 rounded-lg text-sm text-neutral-300 font-mono select-all" />
                    <button phx-hook="CopyToClipboard" data-copy={url(~p"/r/#{@room.code}")} id="copy-invite-link-modal" class="px-3 py-2 bg-white text-black text-sm rounded-lg hover:bg-neutral-200 cursor-pointer">Copy</button>
                  </div>
                </div>
              <% end %>

              <div class="space-y-3">
                <div class="text-xs text-neutral-500 uppercase tracking-wider">Add Member</div>
                <form phx-change="search_member_invite" phx-submit="search_member_invite">
                   <div class="relative">
                     <input type="text" name="query" value={@member_invite_search} placeholder="Search username..." class="w-full px-3 py-2 bg-neutral-950 border border-neutral-800 rounded-lg text-sm text-white focus:outline-none focus:border-neutral-600" autocomplete="off" phx-debounce="300" />
                   </div>
                </form>

                <%= if @member_invite_results != [] do %>
                  <div class="mt-2 max-h-48 overflow-y-auto space-y-1">
                    <%= for user <- @member_invite_results do %>
                       <div class="flex items-center justify-between p-2 hover:bg-neutral-800 rounded-lg group">
                         <div class="flex items-center gap-2">
                           <div class="w-6 h-6 rounded-full" style={"background-color: #{trusted_user_color(user)}"} />
                           <span class="text-sm text-neutral-300">@{user.username}</span>
                         </div>
                         <button phx-click="invite_to_room" phx-value-user_id={user.id} class="text-xs text-blue-400 hover:text-white px-2 py-1 bg-blue-500/10 hover:bg-blue-600 rounded cursor-pointer">Invite</button>
                       </div>
                    <% end %>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>

        <%!-- Name Modal --%>
        <%= if @show_name_modal do %>
          <div class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80" phx-click-away="close_name_modal">
            <div class="w-full max-w-sm bg-neutral-900 border border-neutral-800 p-6">
              <div class="flex items-center justify-between mb-6">
                <h2 class="text-sm font-medium">identity</h2>
                <button type="button" phx-click="close_name_modal" class="text-neutral-500 hover:text-white cursor-pointer">×</button>
              </div>

              <div class="mb-6 flex items-center gap-3">
                <div class="w-8 h-8 rounded-full" style={"background-color: #{@user_color || "#666"}"} />
                <div>
                  <div class="text-sm">{@user_name || "anonymous"}</div>
                  <div class="text-xs text-neutral-600">{if @user_id, do: String.slice(@user_id, 0, 12) <> "...", else: "..."}</div>
                </div>
              </div>

              <form phx-submit="save_name">
                <label class="block text-xs text-neutral-500 mb-2">display name</label>
                <div class="flex gap-2">
                  <input
                    type="text"
                    name="name"
                    value={@name_input}
                    phx-change="update_name_input"
                    placeholder="max 20 chars"
                    maxlength="20"
                    class="flex-1 px-3 py-2 bg-neutral-950 border border-neutral-800 text-sm text-white placeholder:text-neutral-700 focus:outline-none focus:border-neutral-600"
                  />
                  <button type="submit" class="px-4 py-2 bg-white text-black text-sm hover:bg-neutral-200 cursor-pointer">
                    save
                  </button>
                </div>
              </form>

              <p class="mt-4 text-xs text-neutral-600">
                your identity is linked to this device. no account needed.
              </p>
            </div>
          </div>
        <% end %>

        <%!-- Note Modal --%>
        <%= if @show_note_modal do %>
          <div id="note-modal-overlay" class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80" phx-click-away="close_note_modal" phx-hook="LockScroll">
            <div class="w-full max-w-md mx-4 bg-neutral-900 border border-neutral-800 p-4 sm:p-6">
              <div class="flex items-center justify-between mb-4 sm:mb-6">
                <h2 class="text-sm font-medium">new note</h2>
                <button type="button" phx-click="close_note_modal" class="w-11 h-11 flex items-center justify-center text-neutral-500 hover:text-white cursor-pointer text-2xl transition-colors" aria-label="Close note dialog">×</button>
              </div>

              <form phx-submit="save_note" phx-change="update_note">
                <textarea
                  name="content"
                  value={@note_input}
                  placeholder="write something..."
                  maxlength="500"
                  rows="5"
                  class="w-full px-3 py-2 bg-neutral-950 border border-neutral-800 text-sm text-white placeholder:text-neutral-700 focus:outline-none focus:border-neutral-600 resize-none"
                  autofocus
                >{@note_input}</textarea>
                <div class="flex items-center justify-between mt-3">
                  <span class="text-xs text-neutral-600">{String.length(@note_input)}/500</span>
                  <button
                    type="submit"
                    disabled={String.trim(@note_input) == ""}
                    class="px-4 py-2 bg-white text-black text-sm hover:bg-neutral-200 disabled:opacity-50 disabled:cursor-not-allowed cursor-pointer"
                  >
                    share
                  </button>
                </div>
              </form>
            </div>
          </div>
        <% end %>

        <%!-- Network Modal --%>
        <%= if @show_network_modal && @current_user do %>
          <div id="network-modal-overlay" class="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/80 backdrop-blur-sm" phx-click-away="close_network_modal" phx-hook="LockScroll">
            <div class="w-full sm:max-w-md sm:mx-4 bg-neutral-950 sm:rounded-2xl max-h-[90vh] sm:max-h-[85vh] overflow-hidden flex flex-col rounded-t-2xl sm:border sm:border-white/10">
              <%!-- Header --%>
              <div class="relative px-5 pt-5 pb-4 border-b border-white/5">
                <button
                  type="button"
                  phx-click="close_network_modal"
                  class="absolute top-4 right-4 w-8 h-8 flex items-center justify-center text-neutral-500 hover:text-white rounded-full hover:bg-white/10 transition-all cursor-pointer"
                >
                  <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                  </svg>
                </button>

                <div class="flex items-center justify-between pr-10">
                  <div>
                    <div class="text-xl font-semibold text-white">Network</div>
                    <div class="text-sm text-neutral-500">Manage your trusted connections</div>
                  </div>
                  <a
                    href="/graph"
                    class="flex items-center gap-2 px-3 py-2 bg-violet-500/20 rounded-lg hover:bg-violet-500/30 transition-colors group"
                  >
                    <span class="text-lg">🕸️</span>
                    <span class="text-sm font-medium text-violet-300 group-hover:text-violet-200">Graph</span>
                  </a>
                </div>

                <%!-- Tab navigation --%>
                <div class="flex gap-1 mt-6 -mb-4 relative">
                  <button
                    type="button"
                    phx-click="switch_network_tab"
                    phx-value-tab="friends"
                    class={[
                      "px-4 py-2.5 text-sm font-medium rounded-t-lg transition-all relative cursor-pointer",
                      @network_tab == "friends" && "text-white bg-neutral-900",
                      @network_tab != "friends" && "text-neutral-500 hover:text-neutral-300"
                    ]}
                  >
                    Friends
                    <%= if length(@pending_requests) > 0 do %>
                      <span class="absolute -top-1 -right-1 w-5 h-5 bg-amber-500 text-black text-xs font-bold rounded-full flex items-center justify-center">
                        {length(@pending_requests)}
                      </span>
                    <% end %>
                  </button>
                  <button
                    type="button"
                    phx-click="switch_network_tab"
                    phx-value-tab="invites"
                    class={[
                      "px-4 py-2.5 text-sm font-medium rounded-t-lg transition-all cursor-pointer",
                      @network_tab == "invites" && "text-white bg-neutral-900",
                      @network_tab != "invites" && "text-neutral-500 hover:text-neutral-300"
                    ]}
                  >
                    Invites
                  </button>
                </div>
              </div>

              <%!-- Content --%>
              <div class="flex-1 overflow-y-auto bg-neutral-900">
                <%!-- Friends Tab --%>
                <%= if @network_tab == "friends" do %>
                  <div class="p-5 space-y-5">
                    <%!-- Pending requests (incoming) --%>
                    <%= if @pending_requests != [] do %>
                      <div>
                        <div class="text-xs font-semibold text-amber-400 uppercase tracking-wider mb-3">
                          Requests ({length(@pending_requests)})
                        </div>
                        <div class="space-y-2">
                          <%= for req <- @pending_requests do %>
                            <div class="flex items-center justify-between p-3 bg-amber-500/10 rounded-xl border border-amber-500/20">
                              <div class="flex items-center gap-3">
                                <div class="w-9 h-9 rounded-full bg-amber-500/30" />
                                <div>
                                  <div class="text-sm font-medium text-white">@{req.user.username}</div>
                                  <div class="text-xs text-amber-400/70">wants to trust you</div>
                                </div>
                              </div>
                              <button
                                type="button"
                                phx-click="confirm_trust"
                                phx-value-user_id={req.user_id}
                                phx-disable-with="..."
                                class="px-4 py-2 text-xs font-semibold text-black bg-amber-500 hover:bg-amber-400 rounded-lg transition-colors"
                              >
                                Accept
                              </button>
                            </div>
                          <% end %>
                        </div>
                      </div>
                    <% end %>

                    <%!-- Trusted friends --%>
                    <div>
                      <div class="flex items-center justify-between mb-3">
                        <div class="text-xs font-semibold text-neutral-500 uppercase tracking-wider">
                          Trusted ({length(@trusted_friends)}/5)
                        </div>
                        <div class="group relative flex items-center">
                            <span class="cursor-help text-neutral-500 hover:text-neutral-300">ℹ️</span>
                            <div class="absolute right-0 bottom-full mb-2 w-48 p-2 bg-black border border-neutral-800 text-xs text-neutral-300 rounded-lg hidden group-hover:block z-50">
                                Trusted friends can help you recover your account if you lose your key.
                            </div>
                        </div>
                      </div>

                      <%!-- Search --%>
                      <form phx-change="search_friends" class="mb-4">
                        <div class="relative">
                          <svg class="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-neutral-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
                          </svg>
                          <input
                            type="text"
                            name="query"
                            value={@friend_search}
                            placeholder="Search users to add..."
                            autocomplete="off"
                            phx-debounce="300"
                            class="w-full pl-10 pr-4 py-3 bg-neutral-950 border border-white/5 rounded-xl text-sm text-white placeholder:text-neutral-600 focus:outline-none focus:border-white/20 transition-colors"
                          />
                        </div>
                      </form>

                      <%!-- Search results --%>
                      <%= if @friend_search_results != [] do %>
                        <div class="space-y-2 mb-4">
                          <%= for user <- @friend_search_results do %>
                            <div class="flex items-center justify-between p-3 bg-neutral-950 rounded-xl border border-white/5">
                              <div class="flex items-center gap-3">
                                <div class="w-9 h-9 rounded-full bg-neutral-800" />
                                <span class="text-sm font-medium text-white">@{user.username}</span>
                              </div>
                              <button
                                type="button"
                                phx-click="add_trusted_friend"
                                phx-value-user_id={user.id}
                                phx-disable-with="..."
                                class="px-4 py-2 text-xs font-semibold text-green-400 bg-green-500/10 hover:bg-green-500/20 rounded-lg transition-colors"
                              >
                                + Trust
                              </button>
                            </div>
                          <% end %>
                        </div>
                      <% end %>

                      <%!-- Current friends list --%>
                      <div class="space-y-2">
                        <%= if Enum.empty?(@trusted_friends) do %>
                          <div class="text-center py-8">
                            <div class="text-3xl mb-2">👥</div>
                            <div class="text-sm text-neutral-500">No trusted friends yet</div>
                            <div class="text-xs text-neutral-600 mt-1">Search above to add friends</div>
                          </div>
                        <% else %>
                          <%= for tf <- @trusted_friends do %>
                            <div class="flex items-center gap-3 p-3 bg-neutral-950/50 rounded-xl border border-white/5">
                              <div class="w-9 h-9 rounded-full bg-green-500/20 flex items-center justify-center">
                                <svg class="w-4 h-4 text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
                                </svg>
                              </div>
                              <div class="flex-1">
                                <div class="text-sm font-medium text-white">@{tf.trusted_user.username}</div>
                                <div class="text-xs text-green-500/70">Confirmed</div>
                              </div>
                            </div>
                          <% end %>
                        <% end %>
                      </div>
                    </div>

                    <%!-- Outgoing requests --%>
                    <%= if @outgoing_trust_requests != [] do %>
                      <div>
                        <div class="text-xs font-semibold text-neutral-500 uppercase tracking-wider mb-3">
                          Pending sent
                        </div>
                        <div class="space-y-2">
                          <%= for req <- @outgoing_trust_requests do %>
                            <div class="flex items-center gap-3 p-3 bg-neutral-950/50 rounded-xl border border-white/5">
                              <div
                                class="w-9 h-9 rounded-full"
                                style={"background-color: #{trusted_user_color(req.trusted_user)}33"}
                              />
                              <div class="flex-1">
                                <div class="text-sm font-medium text-white">@{req.trusted_user.username}</div>
                                <div class="text-xs text-neutral-500">Awaiting response</div>
                              </div>
                              <div class="w-2 h-2 rounded-full bg-neutral-600 animate-pulse" />
                            </div>
                          <% end %>
                        </div>
                      </div>
                    <% end %>
                  </div>
                <% end %>

                <%!-- Invites Tab --%>
                <%= if @network_tab == "invites" do %>
                  <div class="p-5 space-y-5">
                    <div class="flex items-center justify-between">
                      <div>
                        <div class="text-sm font-medium text-white">Invite Codes</div>
                        <div class="text-xs text-neutral-500">Share to invite new users</div>
                      </div>
                      <button
                        type="button"
                        phx-click="create_invite"
                        phx-disable-with="..."
                        class="px-4 py-2 text-xs font-semibold text-white bg-gradient-to-r from-violet-500 to-blue-500 hover:from-violet-400 hover:to-blue-400 rounded-lg transition-all"
                      >
                        + New Invite
                      </button>
                    </div>

                    <div class="space-y-2">
                      <%= if Enum.empty?(@invites) do %>
                        <div class="text-center py-12">
                          <div class="text-4xl mb-3">🎟️</div>
                          <div class="text-sm text-neutral-500">No invite codes yet</div>
                          <div class="text-xs text-neutral-600 mt-1">Create one to invite friends</div>
                        </div>
                      <% else %>
                        <%= for invite <- @invites do %>
                          <div class={[
                            "p-4 rounded-xl border transition-all",
                            invite.status == "active" && "bg-neutral-950/50 border-white/5",
                            invite.status == "used" && "bg-neutral-950/30 border-white/[0.02] opacity-60"
                          ]}>
                            <div class="flex items-center justify-between">
                              <div class="flex items-center gap-3">
                                <div class={[
                                  "w-10 h-10 rounded-lg flex items-center justify-center text-lg",
                                  invite.status == "active" && "bg-green-500/20",
                                  invite.status == "used" && "bg-neutral-800"
                                ]}>
                                  <%= if invite.status == "active" do %>
                                    🎟️
                                  <% else %>
                                    ✓
                                  <% end %>
                                </div>
                                <div>
                                  <code class="text-sm font-mono text-white">{invite.code}</code>
                                  <div class={[
                                    "text-xs mt-0.5",
                                    invite.status == "active" && "text-green-500",
                                    invite.status == "used" && "text-neutral-500"
                                  ]}>
                                    {invite.status}
                                  </div>
                                </div>
                              </div>
                              <%= if invite.status == "active" do %>
                                <button
                                  type="button"
                                  onclick={"navigator.clipboard.writeText('#{invite.code}')"}
                                  class="px-3 py-1.5 text-xs text-neutral-400 hover:text-white bg-white/5 hover:bg-white/10 rounded-lg transition-all"
                                >
                                  Copy
                                </button>
                              <% end %>
                            </div>
                          </div>
                        <% end %>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>

        <%!-- Settings Modal - Redesigned --%>
        <%= if @show_settings_modal && @current_user do %>
          <div id="settings-modal-overlay" class="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/80 backdrop-blur-sm" phx-click-away="close_settings_modal" phx-hook="LockScroll">
            <div class="w-full sm:max-w-md sm:mx-4 bg-neutral-950 sm:rounded-2xl max-h-[90vh] sm:max-h-[85vh] overflow-hidden flex flex-col rounded-t-2xl sm:border sm:border-white/10">
              <%!-- Header with profile --%>
              <div class="relative px-5 pt-5 pb-4 border-b border-white/5">
                <%!-- Close button --%>
                <button
                  type="button"
                  phx-click="close_settings_modal"
                  class="absolute top-4 right-4 w-8 h-8 flex items-center justify-center text-neutral-500 hover:text-white rounded-full hover:bg-white/10 transition-all cursor-pointer"
                >
                  <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                  </svg>
                </button>

                <%!-- Profile info --%>
                <div class="flex items-center gap-4">
                  <div class="relative">
                    <div
                      class="w-14 h-14 rounded-full shadow-lg shadow-black/30"
                      style={"background: linear-gradient(135deg, #{@user_color} 0%, #{@user_color}88 100%)"}
                    />
                    <div class="absolute -bottom-0.5 -right-0.5 w-4 h-4 bg-green-500 rounded-full border-2 border-neutral-950" />
                  </div>
                  <div class="flex-1 min-w-0">
                    <div class="text-lg font-semibold text-white truncate">
                      {@current_user.display_name || @current_user.username}
                    </div>
                    <div class="text-sm text-neutral-500">@{@current_user.username}</div>
                  </div>
                </div>

                <%!-- Tab navigation --%>
                <div class="flex gap-1 mt-4 -mb-4 relative">
                  <button
                    type="button"
                    phx-click="switch_settings_tab"
                    phx-value-tab="profile"
                    class={[
                      "px-4 py-2.5 text-sm font-medium rounded-t-lg transition-all relative cursor-pointer",
                      @settings_tab == "profile" && "text-white bg-neutral-900",
                      @settings_tab != "profile" && "text-neutral-500 hover:text-neutral-300"
                    ]}
                  >
                    Profile
                  </button>

                  <%= if @room.is_private and @room.owner_id == @current_user.id do %>
                    <button
                      type="button"
                      phx-click="switch_settings_tab"
                      phx-value-tab="room"
                      class={[
                        "px-4 py-2.5 text-sm font-medium rounded-t-lg transition-all cursor-pointer",
                        @settings_tab == "room" && "text-white bg-neutral-900",
                        @settings_tab != "room" && "text-neutral-500 hover:text-neutral-300"
                      ]}
                    >
                      Room
                    </button>
                  <% end %>
                </div>
              </div>

              <%!-- Tab content --%>
              <div class="flex-1 overflow-y-auto bg-neutral-900">
                <%!-- Profile Tab --%>
                <%= if @settings_tab == "profile" do %>
                  <div class="p-5 space-y-4">
                    <%!-- Quick actions grid --%>
                    <div class="grid grid-cols-3 gap-3">
                      <a
                        href="/devices"
                        class="flex items-center gap-3 p-4 bg-neutral-950/50 rounded-xl border border-white/5 hover:border-white/10 hover:bg-neutral-950 transition-all group"
                      >
                        <div class="w-10 h-10 rounded-lg bg-blue-500/20 flex items-center justify-center text-lg">
                          🔐
                        </div>
                        <div>
                          <div class="text-sm font-medium text-white group-hover:text-blue-300 transition-colors">Devices</div>
                          <div class="text-xs text-neutral-600">Security keys</div>
                        </div>
                      </a>
                      <a
                        href="/link"
                        class="flex items-center gap-3 p-4 bg-neutral-950/50 rounded-xl border border-white/5 hover:border-white/10 hover:bg-neutral-950 transition-all group"
                      >
                        <div class="w-10 h-10 rounded-lg bg-emerald-500/20 flex items-center justify-center text-lg">
                          📱
                        </div>
                        <div>
                          <div class="text-sm font-medium text-white group-hover:text-emerald-300 transition-colors">Link</div>
                          <div class="text-xs text-neutral-600">Add device</div>
                        </div>
                      </a>
                      <a
                        href="/recover"
                        class="flex items-center gap-3 p-4 bg-neutral-950/50 rounded-xl border border-white/5 hover:border-white/10 hover:bg-neutral-950 transition-all group"
                      >
                        <div class="w-10 h-10 rounded-lg bg-amber-500/20 flex items-center justify-center text-lg">
                          🔑
                        </div>
                        <div>
                          <div class="text-sm font-medium text-white group-hover:text-amber-300 transition-colors">Recover</div>
                          <div class="text-xs text-neutral-600">Lost access?</div>
                        </div>
                      </a>
                    </div>

                    <%!-- Recovery Requests (urgent) --%>
                    <%= if @recovery_requests != [] do %>
                      <div class="p-4 bg-red-500/10 rounded-xl border border-red-500/20">
                        <div class="flex items-center gap-2 mb-3">
                          <span class="text-red-400">🚨</span>
                          <span class="text-sm font-medium text-red-400">Friends need help recovering</span>
                        </div>
                        <div class="space-y-2">
                          <%= for req <- @recovery_requests do %>
                            <div class="p-3 bg-black/30 rounded-lg">
                              <p class="text-sm text-white mb-2">@{req.username}</p>
                              <p class="text-xs text-neutral-500 mb-3">
                                Verify their identity before confirming
                              </p>
                              <div class="flex gap-2">
                                <button
                                  type="button"
                                  phx-click="vote_recovery"
                                  phx-value-user_id={req.id}
                                  phx-value-vote="confirm"
                                  phx-disable-with="..."
                                  class="flex-1 px-3 py-2 bg-green-500 text-black text-xs font-semibold rounded-lg hover:bg-green-400 transition-colors"
                                >
                                  Confirm
                                </button>
                                <button
                                  type="button"
                                  phx-click="vote_recovery"
                                  phx-value-user_id={req.id}
                                  phx-value-vote="deny"
                                  phx-disable-with="..."
                                  class="flex-1 px-3 py-2 border border-neutral-700 text-neutral-400 text-xs font-medium rounded-lg hover:border-red-500 hover:text-red-400 transition-colors"
                                >
                                  Deny
                                </button>
                              </div>
                            </div>
                          <% end %>
                        </div>
                      </div>
                    <% end %>

                    <%!-- Thumbnails --%>
                    <div class="flex items-center justify-between p-4 bg-neutral-950/50 rounded-xl border border-white/5">
                      <div>
                        <div class="text-sm font-medium text-white">Thumbnails</div>
                        <div class="text-xs text-neutral-500">Regenerate missing previews</div>
                      </div>
                      <button
                        type="button"
                        phx-click="regenerate_thumbnails"
                        phx-disable-with="..."
                        class="px-4 py-2 text-xs font-medium text-blue-400 hover:text-blue-300 bg-blue-500/10 hover:bg-blue-500/20 rounded-lg transition-all"
                      >
                        Regenerate
                      </button>
                    </div>

                    <%!-- Sign out --%>
                    <button
                      type="button"
                      phx-click="sign_out"
                      class="w-full flex items-center justify-center gap-2 p-4 text-sm font-medium text-red-400 hover:text-red-300 bg-red-500/5 hover:bg-red-500/10 rounded-xl border border-red-500/10 hover:border-red-500/20 transition-all"
                    >
                      <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1" />
                      </svg>
                      Sign out
                    </button>
                    <p class="text-xs text-neutral-600 text-center">
                      This will clear your crypto keys from this browser
                    </p>
                  </div>
                <% end %>



                <%!-- Room Tab (only for private room owners) --%>
                <%= if @settings_tab == "room" and @room.is_private and @room.owner_id == @current_user.id do %>
                  <div class="p-5 space-y-5">
                    <div class="flex items-center gap-3 p-4 bg-emerald-500/10 rounded-xl border border-emerald-500/20">
                      <span class="text-2xl">🔒</span>
                      <div>
                        <div class="text-sm font-medium text-emerald-400">{@room.name || @room.code}</div>
                        <div class="text-xs text-emerald-500/70">Private room - {length(@room_members)} members</div>
                      </div>
                    </div>

                    <%!-- Search to invite --%>
                    <div>
                      <div class="text-xs font-semibold text-neutral-500 uppercase tracking-wider mb-3">
                        Invite Members
                      </div>
                      <form phx-change="search_member_invite">
                        <div class="relative">
                          <svg class="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-neutral-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
                          </svg>
                          <input
                            type="text"
                            name="query"
                            value={@member_invite_search}
                            placeholder="Search users to invite..."
                            autocomplete="off"
                            phx-debounce="300"
                            class="w-full pl-10 pr-4 py-3 bg-neutral-950 border border-white/5 rounded-xl text-sm text-white placeholder:text-neutral-600 focus:outline-none focus:border-white/20 transition-colors"
                          />
                        </div>
                      </form>

                      <%= if @member_invite_results != [] do %>
                        <div class="space-y-2 mt-3">
                          <%= for user <- @member_invite_results do %>
                            <div class="flex items-center justify-between p-3 bg-neutral-950 rounded-xl border border-white/5">
                              <div class="flex items-center gap-3">
                                <div class="w-9 h-9 rounded-full bg-neutral-800" />
                                <span class="text-sm font-medium text-white">@{user.username}</span>
                              </div>
                              <button
                                type="button"
                                phx-click="invite_to_room"
                                phx-value-user_id={user.id}
                                phx-disable-with="..."
                                class="px-4 py-2 text-xs font-semibold text-emerald-400 bg-emerald-500/10 hover:bg-emerald-500/20 rounded-lg transition-colors"
                              >
                                + Invite
                              </button>
                            </div>
                          <% end %>
                        </div>
                      <% end %>
                    </div>

                    <%!-- Members list --%>
                    <div>
                      <div class="text-xs font-semibold text-neutral-500 uppercase tracking-wider mb-3">
                        Members
                      </div>
                      <div class="space-y-2">
                        <%= for member <- @room_members do %>
                          <div class="flex items-center gap-3 p-3 bg-neutral-950/50 rounded-xl border border-white/5">
                            <div class={[
                              "w-9 h-9 rounded-full flex items-center justify-center",
                              member.role == "owner" && "bg-amber-500/20",
                              member.role != "owner" && "bg-neutral-800"
                            ]}>
                              <%= if member.role == "owner" do %>
                                <svg class="w-4 h-4 text-amber-400" fill="currentColor" viewBox="0 0 20 20">
                                  <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
                                </svg>
                              <% end %>
                            </div>
                            <div class="flex-1">
                              <div class="text-sm font-medium text-white">@{member.user.username}</div>
                              <div class={[
                                "text-xs",
                                member.role == "owner" && "text-amber-500/70",
                                member.role != "owner" && "text-neutral-500"
                              ]}>
                                {member.role}
                              </div>
                            </div>
                            <%= if member.role != "owner" do %>
                              <button
                                type="button"
                                phx-click="remove_room_member"
                                phx-value-user_id={member.user_id}
                                class="p-2 text-neutral-600 hover:text-red-400 hover:bg-red-500/10 rounded-lg transition-all"
                              >
                                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                                </svg>
                              </button>
                            <% end %>
                          </div>
                        <% end %>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>

        <%!-- Image Modal --%>
        <%= if @show_image_modal && @full_image_data do %>
          <div
            id="photo-modal"
            phx-hook="PhotoModal"
            class="fixed inset-0 z-50 flex items-center justify-center p-4 sm:p-8 modal-backdrop"
            phx-click-away="close_image_modal"
            role="dialog"
            aria-modal="true"
            aria-label="Photo viewer"
          >
            <button
              type="button"
              phx-click="prev_photo"
              class="absolute left-2 sm:left-6 top-1/2 -translate-y-1/2 w-11 h-11 flex items-center justify-center glass rounded-full text-white hover:text-neutral-300 text-2xl cursor-pointer border border-white/10 hover:border-white/20 transition-all z-10"
              aria-label="Previous photo"
            >
              ‹
            </button>

            <div class="relative max-w-6xl max-h-[90vh] flex items-center justify-center">
              <button type="button" phx-click="close_image_modal" class="absolute -top-12 sm:-top-14 right-0 w-11 h-11 flex items-center justify-center glass rounded-full text-white hover:text-neutral-300 text-2xl cursor-pointer border border-white/10 hover:border-white/20 transition-all z-10" aria-label="Close photo viewer">×</button>

              <%= if @full_image_data[:user_id] == @user_id do %>
                <button
                  type="button"
                  phx-click="delete_photo"
                  phx-value-id={@full_image_data[:photo_id]}
                  data-confirm="delete?"
                  class="absolute -top-12 sm:-top-14 left-0 w-16 h-11 flex items-center justify-center glass rounded-full text-red-400 hover:text-red-200 text-xs cursor-pointer border border-white/10 hover:border-white/20 transition-all z-10"
                  aria-label="Delete this photo"
                >
                  delete
                </button>
              <% end %>

              <div class="relative rounded-2xl overflow-hidden opal-glow touch-none">
                <img
                  src={@full_image_data.data}
                  alt="Full size photo"
                  class="max-w-full max-h-[85vh] object-contain"
                />
              </div>
            </div>

            <button
              type="button"
              phx-click="next_photo"
              class="absolute right-2 sm:right-6 top-1/2 -translate-y-1/2 w-11 h-11 flex items-center justify-center glass rounded-full text-white hover:text-neutral-300 text-2xl cursor-pointer border border-white/10 hover:border-white/20 transition-all z-10"
              aria-label="Next photo"
            >
              ›
            </button>
          </div>
        <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # --- Events ---

  def handle_event("set_user_id", %{"browser_id" => browser_id, "fingerprint" => fingerprint}, socket) do
    room = socket.assigns.room

    # Register device for tracking
    {:ok, device, _status} = Social.register_device(fingerprint, browser_id)

    # If user is already authenticated via session cookie (set during WebAuthn login),
    # we just need to track presence. No additional client-side auth needed.
    case socket.assigns.current_user do
      nil ->
        # No authenticated user - use anonymous device identity
        user_id = device.master_id
        user_color = generate_user_color(user_id)
        user_name = device.user_name

        # Check access for private rooms (anonymous users can't access)
        can_access = Social.can_access_room?(room, nil)

        Presence.track_user(self(), room.code, user_id, user_color, user_name)
        viewers = Presence.list_users(room.code)

        {:noreply,
         socket
         |> assign(:user_id, user_id)
         |> assign(:user_color, user_color)
         |> assign(:user_name, user_name)
         |> assign(:auth_status, :anonymous)
         |> assign(:browser_id, browser_id)
         |> assign(:fingerprint, fingerprint)
         |> assign(:viewers, viewers)
         |> assign(:room_access_denied, not can_access)}

      user ->
        # User already authenticated via session cookie (WebAuthn login)
        # Just link device and refresh presence
        Social.link_device_to_user(browser_id, user.id)

        user_id = "user-#{user.id}"
        color = Enum.at(@colors, rem(user.id, length(@colors)))
        user_name = user.display_name || user.username

        can_access = Social.can_access_room?(room, user.id)

        if can_access do
          Presence.track_user(self(), room.code, user_id, color, user_name)
        end

        viewers = if can_access, do: Presence.list_users(room.code), else: []

        {:noreply,
         socket
         |> assign(:user_id, user_id)
         |> assign(:user_color, color)
         |> assign(:user_name, user_name)
         |> assign(:auth_status, :authed)
         |> assign(:browser_id, browser_id)
         |> assign(:fingerprint, fingerprint)
         |> assign(:viewers, viewers)
         |> assign(:room_access_denied, not can_access)}
    end
  end

  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("save", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :photo, ref)}
  end

  def handle_event("delete_photo", %{"id" => id}, socket) do
    case safe_to_integer(id) do
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "invalid id")}

      {:ok, photo_id} ->
        case Social.get_photo(photo_id) do
          nil ->
            {:noreply, put_flash(socket, :error, "not found")}

          photo ->
            if photo.user_id == socket.assigns.user_id do
              case Social.delete_photo(photo_id, socket.assigns.room.code) do
                {:ok, _} ->
                  {:noreply,
                   socket
                   |> assign(:item_count, max(0, socket.assigns.item_count - 1))
                   |> maybe_close_deleted_photo(photo_id)
                   |> assign(:photo_order, remove_photo_from_order(socket.assigns.photo_order, photo_id))
                   |> stream_delete(:items, %{id: photo_id, unique_id: "photo-#{photo_id}"})}

                {:error, _} ->
                  {:noreply, put_flash(socket, :error, "failed")}
              end
            else
              {:noreply, put_flash(socket, :error, "not yours")}
            end
        end
    end
  end

  def handle_event("delete_note", %{"id" => id}, socket) do
    case safe_to_integer(id) do
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "invalid id")}

      {:ok, note_id} ->
        case Social.delete_note(note_id, socket.assigns.user_id, socket.assigns.room.code) do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(:item_count, max(0, socket.assigns.item_count - 1))
             |> stream_delete(:items, %{id: note_id, unique_id: "note-#{note_id}"})}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "cannot delete")}
        end
    end
  end

  # Room events
  def handle_event("open_room_modal", _params, socket) do
    {:noreply, socket |> assign(:show_room_modal, true)}
  end

  def handle_event("close_room_modal", _params, socket) do
    {:noreply, assign(socket, :show_room_modal, false)}
  end

  # Create Group modal events
  def handle_event("open_create_group_modal", _params, socket) do
    if socket.assigns.current_user do
      {:noreply, socket |> assign(:create_group_modal, true) |> assign(:new_room_name, "")}
    else
      {:noreply, put_flash(socket, :error, "please login to create groups")}
    end
  end

  def handle_event("close_create_group_modal", _params, socket) do
    {:noreply, socket |> assign(:create_group_modal, false) |> assign(:new_room_name, "")}
  end

  def handle_event("create_group", %{"name" => name}, socket) do
    name = String.trim(name)
    
    case socket.assigns.current_user do
      nil ->
        {:noreply, put_flash(socket, :error, "please login to create groups")}
      
      user ->
        code = Social.generate_room_code()
        group_name = if name == "", do: nil, else: name
        
        case Social.create_private_room(%{code: code, name: group_name, created_by: socket.assigns.user_id}, user.id) do
          {:ok, _room} ->
            {:noreply,
             socket
             |> assign(:create_group_modal, false)
             |> assign(:new_room_name, "")
             |> push_navigate(to: ~p"/r/#{code}")}
          
          {:error, _} ->
            {:noreply, put_flash(socket, :error, "failed to create group")}
        end
    end
  end

  def handle_event("update_join_code", %{"code" => code}, socket) do
    {:noreply, assign(socket, :join_code, code)}
  end

  def handle_event("update_room_name", %{"name" => name}, socket) do
    {:noreply, assign(socket, :new_room_name, name)}
  end

  def handle_event("update_room_form", params, socket) do
    name = params["name"] || ""
    is_private = params["is_private"] == "on"
    
    {:noreply,
     socket
     |> assign(:new_room_name, name)
     |> assign(:create_private_room, is_private)}
  end

  def handle_event("update_room_invite_username", %{"username" => username}, socket) do
    {:noreply, assign(socket, :room_invite_username, username)}
  end

  def handle_event("add_room_member", %{"username" => username}, socket) do
    room = socket.assigns.room
    owner_id = socket.assigns.current_user && socket.assigns.current_user.id

    cond do
      is_nil(owner_id) ->
        {:noreply, put_flash(socket, :error, "login to invite")}

      room.owner_id != owner_id or not room.is_private ->
        {:noreply, put_flash(socket, :error, "only owners can invite to private spaces")}

      true ->
        user = Social.get_user_by_username(username)

        cond do
          is_nil(user) ->
            {:noreply, put_flash(socket, :error, "user not found")}

          Social.can_access_room?(room, user.id) ->
            {:noreply, put_flash(socket, :info, "@#{user.username} is already a member")}

          true ->
            case Social.add_room_member(room.id, user.id, "member", owner_id) do
              {:ok, _member} ->
                {:noreply,
                 socket
                 |> put_flash(:info, "@#{user.username} added to space")
                 |> assign(:room_invite_username, "")}

              {:error, _} ->
                {:noreply, put_flash(socket, :error, "failed to add user")}
            end
        end
    end
  end

  def handle_event("set_network_filter", %{"filter" => filter}, socket)
      when filter in ["trusted", "all"] do
    socket = assign(socket, :network_filter, filter)

    if socket.assigns.feed_mode == "friends" do
      case socket.assigns.current_user do
        nil ->
          {:noreply, put_flash(socket, :error, "register to see your network")}

        user ->
          {photos, notes} =
            case filter do
              "all" ->
                {Social.list_public_photos(@initial_batch, offset: 0),
                 Social.list_public_notes(@initial_batch, offset: 0)}

              _ ->
                {Social.list_friends_photos(user.id, @initial_batch, offset: 0),
                 Social.list_friends_notes(user.id, @initial_batch, offset: 0)}
            end

          items = build_items(photos, notes)
          no_more = length(items) < @initial_batch

          {:noreply,
           socket
           |> assign(:item_count, length(items))
           |> assign(:no_more_items, no_more)
           |> assign(:photo_order, photo_ids(items))
           |> stream(:items, items, reset: true, dom_id: &("item-#{&1.unique_id}"))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("join_room", %{"code" => code}, socket) do
    code = code |> String.trim() |> String.downcase() |> String.replace(~r/[^a-z0-9-]/, "")

    if code != "" do
      {:noreply,
       socket
       |> assign(:show_room_modal, false)
       |> assign(:join_code, "")
       |> push_navigate(to: ~p"/r/#{code}")}
    else
      {:noreply, put_flash(socket, :error, "enter a room code")}
    end
  end

  def handle_event("create_room", params, socket) do
    name = params["name"]
    is_private = params["is_private"] == "on" || socket.assigns.create_private_room
    code = Social.generate_room_code()
    name = if name == "" or is_nil(name), do: nil, else: String.trim(name)

    result = 
      if is_private do
        case socket.assigns.current_user do
          nil ->
            {:error, :not_registered}
          user ->
            Social.create_private_room(%{code: code, name: name, created_by: socket.assigns.user_id}, user.id)
        end
      else
        Social.create_room(%{code: code, name: name, created_by: socket.assigns.user_id})
      end

    case result do
      {:ok, _room} ->
        {:noreply,
         socket
         |> assign(:show_room_modal, false)
         |> assign(:new_room_name, "")
         |> assign(:create_private_room, false)
         |> push_navigate(to: ~p"/r/#{code}")}

      {:error, :not_registered} ->
        {:noreply, put_flash(socket, :error, "register to create private rooms")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "failed to create")}
    end
  end

  def handle_event("go_to_public_square", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_room_modal, false)
     |> push_navigate(to: ~p"/r/lobby")}
  end

  def handle_event("switch_room", %{"code" => code}, socket) do
    {:noreply,
     socket
     |> assign(:show_room_modal, false)
     |> push_navigate(to: ~p"/r/#{code}")}
  end

  # Name events
  def handle_event("open_name_modal", _params, socket) do
    {:noreply, socket |> assign(:show_name_modal, true) |> assign(:name_input, socket.assigns.user_name || "")}
  end

  def handle_event("close_name_modal", _params, socket) do
    {:noreply, assign(socket, :show_name_modal, false)}
  end

  def handle_event("update_name_input", %{"name" => name}, socket) do
    {:noreply, assign(socket, :name_input, name)}
  end

  def handle_event("save_name", %{"name" => name}, socket) do
    name = String.trim(name)
    name = if name == "", do: nil, else: String.slice(name, 0, 20)

    if name && Social.username_taken?(name, socket.assigns.user_id) do
      {:noreply, put_flash(socket, :error, "name taken")}
    else
      Social.save_username(socket.assigns.browser_id, name)
      Presence.update_user(self(), socket.assigns.room.code, socket.assigns.user_id, socket.assigns.user_color, name)

      {:noreply,
       socket
       |> assign(:user_name, name)
       |> assign(:show_name_modal, false)}
    end
  end

  # Note events
  def handle_event("open_note_modal", _params, socket) do
    # Only registered users can open note modal
    if socket.assigns.current_user && not socket.assigns.room_access_denied do
      {:noreply, socket |> assign(:show_note_modal, true) |> assign(:note_input, "")}
    else
      {:noreply, socket}
    end
  end

  def handle_event("close_note_modal", _params, socket) do
    {:noreply, socket |> assign(:show_note_modal, false) |> assign(:note_input, "")}
  end

  def handle_event("update_note", %{"content" => content}, socket) do
    {:noreply, assign(socket, :note_input, content)}
  end

  def handle_event("save_note", %{"content" => content}, socket) do
    content = String.trim(content)

    # Only registered users can create notes
    if content != "" && socket.assigns.current_user && not socket.assigns.room_access_denied do
      case Social.create_note(
             %{
               user_id: socket.assigns.user_id,
               user_color: socket.assigns.user_color,
               user_name: socket.assigns.user_name,
               content: content,
               room_id: socket.assigns.room.id
             },
             socket.assigns.room.code
           ) do
        {:ok, note} ->
          note_with_type = note |> Map.put(:type, :note) |> Map.put(:unique_id, "note-#{note.id}")

          {:noreply,
           socket
           |> assign(:show_note_modal, false)
           |> assign(:note_input, "")
           |> assign(:item_count, socket.assigns.item_count + 1)
           |> stream_insert(:items, note_with_type, at: 0)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "failed")}
      end
    else
      {:noreply, socket}
    end
  end

  # Thumbnail from JS
  def handle_event("set_thumbnail", %{"photo_id" => photo_id, "thumbnail" => thumbnail}, socket) do
    # Guard against bad payloads; quietly ignore to avoid crashing the view
    if is_nil(thumbnail) do
      {:noreply, socket}
    else
      try do
        photo_id_int = normalize_photo_id(photo_id)

        # Save to DB and broadcast to other clients
        if socket.assigns.user_id && is_binary(thumbnail) do
          Social.set_photo_thumbnail(photo_id_int, thumbnail, socket.assigns.user_id, socket.assigns.room.code)
        end

        # Update the stream for this client immediately using stream_insert
        case Social.get_photo(photo_id_int) do
          nil ->
            {:noreply, socket}

          photo ->
            photo_with_type =
              photo
              |> Map.from_struct()
              |> Map.put(:type, :photo)
              |> Map.put(:unique_id, "photo-#{photo.id}")
              |> Map.put(:thumbnail_data, thumbnail)

            {:noreply, stream_insert(socket, :items, photo_with_type)}
        end
      rescue
        _e ->
          {:noreply, socket}
      end
    end
  end

  # Settings modal events
  def handle_event("open_settings_modal", _params, socket) do
    room = socket.assigns.room

    # Load room members if this is a private room
    members = if room.is_private, do: Social.list_room_members(room.id), else: []

    {:noreply,
     socket
     |> assign(:show_settings_modal, true)
     |> assign(:settings_tab, "profile")
     |> assign(:room_members, members)}
  end

  def handle_event("switch_settings_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :settings_tab, tab)}
  end

  def handle_event("close_settings_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_settings_modal, false)
     |> assign(:settings_tab, "profile")
     |> assign(:member_invite_search, "")
     |> assign(:member_invite_results, [])}
  end

  # Network modal events
  def handle_event("open_network_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_network_modal, true)
     |> assign(:network_tab, "friends")}
  end

  def handle_event("close_network_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_network_modal, false)
     |> assign(:network_tab, "friends")
     |> assign(:friend_search, "")
     |> assign(:friend_search_results, [])}
  end

  def handle_event("switch_network_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :network_tab, tab)}
  end

  def handle_event("sign_out", _params, socket) do
    # Push event to client to clear crypto identity
    {:noreply,
     socket
     |> push_event("sign_out", %{})
     |> put_flash(:info, "Signing out...")}
  end

  def handle_event("view_full_image", %{"photo_id" => photo_id}, socket) do
    {:noreply, load_photo_into_modal(socket, photo_id)}
  end

  def handle_event("close_image_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_image_modal, false)
     |> assign(:full_image_data, nil)
     |> assign(:current_photo_id, nil)}
  end

  def handle_event("next_photo", _params, socket) do
    {:noreply, navigate_photo(socket, :next)}
  end

  def handle_event("prev_photo", _params, socket) do
    {:noreply, navigate_photo(socket, :prev)}
  end

  # Global keyboard handler for accessibility
  def handle_event("handle_keydown", %{"key" => "Escape"}, socket) do
    cond do
      socket.assigns.show_image_modal ->
        {:noreply,
         socket
         |> assign(:show_image_modal, false)
         |> assign(:full_image_data, nil)
         |> assign(:current_photo_id, nil)}

      socket.assigns.show_room_modal ->
        {:noreply, assign(socket, :show_room_modal, false)}

      socket.assigns.create_group_modal ->
        {:noreply, socket |> assign(:create_group_modal, false) |> assign(:new_room_name, "")}

      socket.assigns.show_settings_modal ->
        {:noreply,
         socket
         |> assign(:show_settings_modal, false)
         |> assign(:member_invite_search, "")
         |> assign(:member_invite_results, [])}

      socket.assigns.show_network_modal ->
        {:noreply,
         socket
         |> assign(:show_network_modal, false)
         |> assign(:friend_search, "")
         |> assign(:friend_search_results, [])}

      socket.assigns.show_name_modal ->
        {:noreply, assign(socket, :show_name_modal, false)}

      socket.assigns.show_note_modal ->
        {:noreply, socket |> assign(:show_note_modal, false) |> assign(:note_input, "")}

      true ->
        {:noreply, socket}
    end
  end

  def handle_event("handle_keydown", %{"key" => key}, socket)
      when key in ["ArrowLeft", "ArrowRight"] do
    if socket.assigns.show_image_modal do
      case key do
        "ArrowRight" -> {:noreply, navigate_photo(socket, :next)}
        "ArrowLeft" -> {:noreply, navigate_photo(socket, :prev)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("handle_keydown", _params, socket), do: {:noreply, socket}

  def handle_event("regenerate_thumbnails", _params, socket) do
    # Rate limit: only allow once per 60 seconds per session
    last_regen = socket.assigns[:last_thumbnail_regen] || 0
    now = System.system_time(:second)

    if now - last_regen < 60 do
      {:noreply, put_flash(socket, :error, "Please wait before regenerating again")}
    else
      # Start background task to regenerate missing thumbnails
      Task.async(fn ->
        regenerate_all_missing_thumbnails(socket.assigns.room.id, socket.assigns.room.code)
      end)

      {:noreply,
       socket
       |> assign(:last_thumbnail_regen, now)
       |> put_flash(:info, "Regenerating missing thumbnails in background...")}
    end
  end

  def handle_event("create_invite", _params, socket) do
    case socket.assigns.current_user do
      nil ->
        {:noreply, put_flash(socket, :error, "register first")}
      
      user ->
        case Social.create_invite(user.id) do
          {:ok, invite} ->
            {:noreply, assign(socket, :invites, [invite | socket.assigns.invites])}
          
          {:error, _} ->
            {:noreply, put_flash(socket, :error, "failed to create invite")}
        end
    end
  end

  def handle_event("search_friends", %{"query" => query}, socket) do
    query = String.trim(query)
    
    results = 
      if String.length(query) >= 2 do
        Social.search_users(query, socket.assigns.current_user && socket.assigns.current_user.id)
      else
        []
      end
    
    {:noreply, 
     socket 
     |> assign(:friend_search, query)
     |> assign(:friend_search_results, results)}
  end

  def handle_event("add_trusted_friend", %{"user_id" => user_id_str}, socket) do
    case safe_to_integer(user_id_str) do
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "invalid user")}

      {:ok, user_id} ->
        case socket.assigns.current_user do
          nil ->
            {:noreply, put_flash(socket, :error, "register first")}

          current_user ->
            case Social.add_trusted_friend(current_user.id, user_id) do
              {:ok, _tf} ->
                outgoing = Social.list_sent_trust_requests(current_user.id)
                {:noreply,
                 socket
                 |> assign(:friend_search, "")
                 |> assign(:friend_search_results, [])
                 |> assign(:outgoing_trust_requests, outgoing)
                 |> put_flash(:info, "trust request sent")}

              {:error, :cannot_trust_self} ->
                {:noreply, put_flash(socket, :error, "can't trust yourself")}

              {:error, :max_trusted_friends} ->
                {:noreply, put_flash(socket, :error, "max 5 trusted friends")}

              {:error, _} ->
                {:noreply, put_flash(socket, :error, "already requested")}
            end
        end
    end
  end

  def handle_event("confirm_trust", %{"user_id" => user_id_str}, socket) do
    case safe_to_integer(user_id_str) do
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "invalid user")}

      {:ok, user_id} ->
        case socket.assigns.current_user do
          nil ->
            {:noreply, put_flash(socket, :error, "register first")}

          current_user ->
            case Social.confirm_trusted_friend(current_user.id, user_id) do
              {:ok, _} ->
                # Refresh the pending requests
                pending = Social.list_pending_trust_requests(current_user.id)
                {:noreply,
                 socket
                 |> assign(:pending_requests, pending)
                 |> put_flash(:info, "trust confirmed")}

              {:error, _} ->
                {:noreply, put_flash(socket, :error, "failed")}
            end
        end
    end
  end

  # --- Room Member Management ---

  def handle_event("search_member_invite", %{"query" => query}, socket) do
    query = String.trim(query)
    current_user = socket.assigns.current_user
    
    results = 
      if String.length(query) >= 2 and current_user do
        # Get current member IDs to exclude
        member_ids = Enum.map(socket.assigns.room_members, & &1.user_id)
        
        Social.search_users(query, current_user.id)
        |> Enum.reject(fn user -> user.id in member_ids end)
      else
        []
      end
    
    {:noreply, 
     socket 
     |> assign(:member_invite_search, query)
     |> assign(:member_invite_results, results)}
  end

  def handle_event("invite_to_room", %{"user_id" => user_id_str}, socket) do
    case safe_to_integer(user_id_str) do
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "invalid user")}

      {:ok, user_id} ->
        room = socket.assigns.room
        current_user = socket.assigns.current_user

        case current_user do
          nil ->
            {:noreply, put_flash(socket, :error, "register first")}

          _ ->
            case Social.invite_to_room(room.id, current_user.id, user_id) do
              {:ok, _member} ->
                # Refresh room members
                members = Social.list_room_members(room.id)
                {:noreply,
                 socket
                 |> assign(:room_members, members)
                 |> assign(:member_invite_search, "")
                 |> assign(:member_invite_results, [])
                 |> put_flash(:info, "member invited")}

              {:error, :not_a_member} ->
                {:noreply, put_flash(socket, :error, "you're not a member")}

              {:error, :not_authorized} ->
                {:noreply, put_flash(socket, :error, "only owners can invite")}

              {:error, _} ->
                {:noreply, put_flash(socket, :error, "invite failed")}
            end
        end
    end
  end

  def handle_event("remove_room_member", %{"user_id" => user_id_str}, socket) do
    case safe_to_integer(user_id_str) do
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "invalid user")}

      {:ok, user_id} ->
        room = socket.assigns.room
        current_user = socket.assigns.current_user

        # Check if current user is owner
        if current_user && room.owner_id == current_user.id do
          Social.remove_room_member(room.id, user_id)
          members = Social.list_room_members(room.id)
          {:noreply,
           socket
           |> assign(:room_members, members)
           |> put_flash(:info, "member removed")}
        else
          {:noreply, put_flash(socket, :error, "only owners can remove members")}
        end
    end
  end

  def handle_event("switch_feed", %{"mode" => mode}, socket) when mode in ["room", "friends"] do
    socket = assign(socket, :feed_mode, mode)
    
    case mode do
      "room" ->
        # Load room content
        room = socket.assigns.room
        photos = Social.list_photos(room.id, @initial_batch, offset: 0)
        notes = Social.list_notes(room.id, @initial_batch, offset: 0)
        items = build_items(photos, notes)
        no_more = length(items) < @initial_batch
        
        {:noreply,
         socket
         |> assign(:item_count, length(items))
         |> assign(:no_more_items, no_more)
         |> assign(:photo_order, photo_ids(items))
         |> stream(:items, items, reset: true, dom_id: &("item-#{&1.unique_id}"))}
      
      "friends" ->
        # Load network content
        case socket.assigns.current_user do
          nil ->
            {:noreply, put_flash(socket, :error, "register to see your network")}

          user ->
            # Load trusted friends for the network display
            trusted_friends = Social.list_trusted_friends(user.id)
            outgoing_trusts = Social.list_sent_trust_requests(user.id)

            {photos, notes} =
              case socket.assigns.network_filter do
                "all" ->
                  {Social.list_public_photos(@initial_batch, offset: 0),
                   Social.list_public_notes(@initial_batch, offset: 0)}

                _ ->
                  {Social.list_friends_photos(user.id, @initial_batch, offset: 0),
                   Social.list_friends_notes(user.id, @initial_batch, offset: 0)}
              end
            items = build_items(photos, notes)
            no_more = length(items) < @initial_batch

            {:noreply,
             socket
             |> assign(:trusted_friends, trusted_friends)
             |> assign(:outgoing_trust_requests, outgoing_trusts)
             |> assign(:item_count, length(items))
             |> assign(:no_more_items, no_more)
             |> assign(:photo_order, photo_ids(items))
             |> stream(:items, items, reset: true, dom_id: &("item-#{&1.unique_id}"))}
        end
    end
  end

  def handle_event("toggle_header_dropdown", _, socket) do
    {:noreply, assign(socket, :show_header_dropdown, !socket.assigns.show_header_dropdown)}
  end

  def handle_event("close_header_dropdown", _, socket) do
    {:noreply, assign(socket, :show_header_dropdown, false)}
  end

  def handle_event("toggle_user_dropdown", _, socket) do
    {:noreply, assign(socket, :show_user_dropdown, !socket.assigns.show_user_dropdown)}
  end

  def handle_event("close_user_dropdown", _, socket) do
    {:noreply, assign(socket, :show_user_dropdown, false)}
  end

  def handle_event("sign_out", _, socket) do
    {:noreply, push_navigate(socket, to: ~p"/login?action=signout")}
  end

  def handle_event("open_invite_modal", _, socket) do
    {:noreply, assign(socket, :show_invite_modal, true)}
  end

  def handle_event("close_invite_modal", _, socket) do
    {:noreply, assign(socket, :show_invite_modal, false)}
  end

  def handle_event("set_feed_view", %{"view" => view}, socket) do
    # 1. Determine new state based on view selection
    {new_mode, new_filter} =
      case view do
        "room" -> {"room", socket.assigns.network_filter}
        "friends" -> {"friends", "trusted"}
        "public" -> {"friends", "all"}
        "me" -> {"friends", "me"}
      end

    socket =
      socket
      |> assign(:feed_mode, new_mode)
      |> assign(:network_filter, new_filter)

    # 2. Fetch content based on the new state
    {items, no_more} =
      case new_mode do
        "room" ->
          room = socket.assigns.room
          photos = Social.list_photos(room.id, @initial_batch, offset: 0)
          notes = Social.list_notes(room.id, @initial_batch, offset: 0)
          items = build_items(photos, notes)
          {items, length(items) < @initial_batch}

        "friends" ->
           case socket.assigns.current_user do
             nil ->
               {[], true}
             user ->
               trusted_friends = Social.list_trusted_friends(user.id)
               outgoing_trusts = Social.list_sent_trust_requests(user.id)

               {photos, notes} =
                 case new_filter do
                   "all" ->
                     {Social.list_public_photos(@initial_batch, offset: 0),
                      Social.list_public_notes(@initial_batch, offset: 0)}
                   "me" ->
                     {Social.list_user_photos(user.id, @initial_batch, offset: 0),
                      Social.list_user_notes(user.id, @initial_batch, offset: 0)}
                   _ ->
                     {Social.list_friends_photos(user.id, @initial_batch, offset: 0),
                      Social.list_friends_notes(user.id, @initial_batch, offset: 0)}
                 end

               items = build_items(photos, notes)

               # We need to update side-assignments as well if we switched to friends mode
               # Although usually these are only displayed if feed_mode == "friends", so we update them now
               # to ensure they are fresh
               {items, length(items) < @initial_batch}
           end
      end

    # 3. Update updates trusted friends / requests if we are in friends mode
    socket =
      if new_mode == "friends" && socket.assigns.current_user do
         user_id = socket.assigns.current_user.id
         socket
         |> assign(:trusted_friends, Social.list_trusted_friends(user_id))
         |> assign(:outgoing_trust_requests, Social.list_sent_trust_requests(user_id))
      else
        socket
      end

  {:noreply,
     socket
     |> assign(:item_count, length(items))
     |> assign(:no_more_items, no_more)
     |> assign(:photo_order, photo_ids(items))
     |> stream(:items, items, reset: true, dom_id: &("item-#{&1.unique_id}"))}
  end

  # Toggle the chat panel visibility in split-view layout
  def handle_event("toggle_chat_panel", _, socket) do
    new_show = not socket.assigns.show_chat_panel
    
    socket = socket
    |> assign(:show_chat_panel, new_show)
    |> assign(:feed_mode, "room")  # Ensure we're in room mode
    
    # Load chat messages and subscribe if opening chat
    socket = if new_show do
      if connected?(socket) do
        Social.subscribe_to_room_chat(socket.assigns.room.id)
      end
      messages = Social.list_room_messages(socket.assigns.room.id, 50)
      assign(socket, :room_messages, messages)
    else
      socket
    end

    {:noreply, socket}
  end

  # Update chat message input
  def handle_event("update_chat_message", %{"value" => text}, socket) do
    {:noreply, assign(socket, :new_chat_message, text)}
  end

  # Send a chat message (encrypted)
  def handle_event("send_room_message", %{"encrypted_content" => encrypted, "nonce" => nonce}, socket) do
    if socket.assigns.current_user do
      case Social.send_room_message(
        socket.assigns.room.id,
        socket.assigns.current_user.id,
        Base.decode64!(encrypted),
        "text",
        %{},
        Base.decode64!(nonce)
      ) do
        {:ok, _message} ->
          {:noreply, assign(socket, :new_chat_message, "")}
        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to send message")}
      end
    else
      {:noreply, socket}
    end
  end

  # Start voice recording
  def handle_event("start_room_recording", _, socket) do
    {:noreply,
     socket
     |> assign(:recording_voice, true)
     |> push_event("start_room_voice_recording", %{})}
  end

  # Stop voice recording
  def handle_event("stop_room_recording", _, socket) do
    {:noreply,
     socket
     |> assign(:recording_voice, false)
     |> push_event("stop_room_voice_recording", %{})}
  end

  # Send voice note (encrypted)
  def handle_event("send_room_voice_note", %{"encrypted_content" => encrypted, "nonce" => nonce, "duration_ms" => duration}, socket) do
    if socket.assigns.current_user do
      case Social.send_room_message(
        socket.assigns.room.id,
        socket.assigns.current_user.id,
        Base.decode64!(encrypted),
        "voice",
        %{"duration_ms" => duration},
        Base.decode64!(nonce)
      ) do
        {:ok, _message} ->
          {:noreply, assign(socket, :recording_voice, false)}
        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to send voice note")}
      end
    else
      {:noreply, socket}
    end
  end

  # Handle new room message from PubSub
  def handle_info({:new_room_message, message}, socket) do
    if socket.assigns.room_tab == "chat" do
      messages = socket.assigns.room_messages ++ [message]
      {:noreply, assign(socket, :room_messages, messages)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("load_more", _params, socket) do
    if socket.assigns.room_access_denied do
      {:noreply, socket}
    else
      if socket.assigns.no_more_items do
        {:noreply, socket}
      else
        batch = @initial_batch
        offset = socket.assigns.item_count || 0
        mode = socket.assigns.feed_mode

      {items, no_more?} =
        case mode do
          "friends" ->
            case socket.assigns.current_user do
              nil -> {[], true}
              user ->
                {photos, notes} =
                  case socket.assigns.network_filter do
                    "all" ->
                      {Social.list_public_photos(batch, offset: offset),
                       Social.list_public_notes(batch, offset: offset)}

                    _ ->
                      {Social.list_friends_photos(user.id, batch, offset: offset),
                       Social.list_friends_notes(user.id, batch, offset: offset)}
                  end
                items = build_items(photos, notes)
                {items, length(items) < batch}
            end

          _ ->
            room = socket.assigns.room
            photos = Social.list_photos(room.id, batch, offset: offset)
            notes = Social.list_notes(room.id, batch, offset: offset)
            items = build_items(photos, notes)
            {items, length(items) < batch}
        end

      new_count = offset + length(items)
      new_photo_order = merge_photo_order(socket.assigns.photo_order, photo_ids(items), :back)

      socket =
        Enum.reduce(items, socket, fn item, acc ->
          stream_insert(acc, :items, item)
        end)

        {:noreply,
         socket
         |> assign(:item_count, new_count)
         |> assign(:no_more_items, no_more?)
         |> assign(:photo_order, new_photo_order)}
      end
    end
  end

  def handle_event("vote_recovery", %{"user_id" => user_id_str, "vote" => vote}, socket) do
    case safe_to_integer(user_id_str) do
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "invalid user")}

      {:ok, user_id} ->
        case socket.assigns.current_user do
          nil ->
            {:noreply, put_flash(socket, :error, "register first")}

          current_user ->
            # Get the new public key from the recovery request
            new_public_key = Social.get_recovery_public_key(user_id)

            if is_nil(new_public_key) do
              {:noreply, put_flash(socket, :error, "no recovery in progress")}
            else
              case Social.cast_recovery_vote(user_id, current_user.id, vote, new_public_key) do
                {:ok, :recovered, _user} ->
                  # Refresh recovery requests
                  recovery_requests = Social.list_recovery_requests_for_voter(current_user.id)
                  {:noreply,
                   socket
                   |> assign(:recovery_requests, recovery_requests)
                   |> put_flash(:info, "vote recorded - account recovered!")}

                {:ok, :votes_recorded, count} ->
                  recovery_requests = Social.list_recovery_requests_for_voter(current_user.id)
                  {:noreply,
                   socket
                   |> assign(:recovery_requests, recovery_requests)
                   |> put_flash(:info, "vote recorded (#{count}/4 needed)")}

                {:error, :not_trusted_friend} ->
                  {:noreply, put_flash(socket, :error, "not a trusted friend")}

                {:error, _} ->
                  {:noreply, put_flash(socket, :error, "already voted")}
              end
            end
        end
    end
  end

  # --- Progress Handler ---

  # Validate file content by checking magic bytes (file signature)
  defp validate_image_content(binary) do
    case binary do
      # JPEG: starts with FF D8 FF
      <<0xFF, 0xD8, 0xFF, _rest::binary>> -> {:ok, "image/jpeg"}
      # PNG: starts with 89 50 4E 47 0D 0A 1A 0A
      <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, _rest::binary>> -> {:ok, "image/png"}
      # GIF: starts with GIF87a or GIF89a
      <<"GIF87a", _rest::binary>> -> {:ok, "image/gif"}
      <<"GIF89a", _rest::binary>> -> {:ok, "image/gif"}
      # WebP: starts with RIFF....WEBP
      <<"RIFF", _size::binary-size(4), "WEBP", _rest::binary>> -> {:ok, "image/webp"}
      _ -> {:error, :invalid_image}
    end
  end

  # Generate thumbnail for photos that don't have one
  # Generate thumbnail from base64 image data
  defp generate_thumbnail_from_data("data:" <> data, photo_id, user_id, room_code) do
    try do
      # Extract the actual base64 data after the comma
      case String.split(data, ",", parts: 2) do
        [mime, base64_data] ->
          case Base.decode64(base64_data) do
            {:ok, binary_data} ->
              # Try to generate a smaller thumbnail; fall back to original data URL
              thumbnail_data =
                generate_server_thumbnail(binary_data) ||
                  "data:#{mime},#{base64_data}"

              Social.set_photo_thumbnail(photo_id, thumbnail_data, user_id, room_code)

            _ ->
              :error
          end

        _ ->
          :error
      end
    rescue
      _ -> :error
    end
  end

  defp generate_thumbnail_from_data(_, _, _, _), do: :error

  # Server-side thumbnail generation (simplified version)
  defp generate_server_thumbnail(binary_data) do
    try do
      # Placeholder for future server-side resizing; return nil so callers fall back to the source data
      _ = byte_size(binary_data)
      nil
    rescue
      _ -> nil
    end
  end

  # Regenerate missing thumbnails for all photos in a room
  defp regenerate_all_missing_thumbnails(room_id, room_code) do
    # Get all photos in the room that don't have thumbnails
    photos_without_thumbnails =
      Social.Photo
      |> where(
        [p],
        p.room_id == ^room_id and
          (is_nil(p.thumbnail_data) or ilike(p.thumbnail_data, ^"data:image/svg+xml%"))
      )
      |> Repo.all()

    # Process each photo
    Enum.each(photos_without_thumbnails, fn photo ->
      if photo.image_data do
        generate_thumbnail_from_data(photo.image_data, photo.id, photo.user_id, room_code)
        # Add small delay to avoid overwhelming the system
        Process.sleep(100)
      end
    end)
  end

  def handle_progress(:photo, entry, socket) when entry.done? do
    # Only registered users with room access can upload
    if is_nil(socket.assigns.current_user) or socket.assigns.room_access_denied do
      {:noreply, put_flash(socket, :error, "Please register to upload photos")}
    else
      [photo_result] =
        consume_uploaded_entries(socket, :photo, fn %{path: path}, _entry ->
          binary = File.read!(path)

          # Validate actual file content, not just extension/client type
          case validate_image_content(binary) do
            {:ok, validated_type} ->
              base64 = Base.encode64(binary)
              file_size = byte_size(binary)
              {:ok, %{data_url: "data:#{validated_type};base64,#{base64}", content_type: validated_type, file_size: file_size}}

            {:error, :invalid_image} ->
              {:ok, %{error: :invalid_image}}
          end
        end)

      # Check if validation failed
      case photo_result do
        %{error: :invalid_image} ->
          {:noreply,
           socket
           |> assign(:uploading, false)
           |> put_flash(:error, "Invalid file type. Please upload a valid image (JPEG, PNG, GIF, or WebP).")}

        %{data_url: _, content_type: _, file_size: _} = valid_result ->
          room = socket.assigns.room

          case Social.create_photo(
                 %{
                   user_id: socket.assigns.user_id,
                   user_color: socket.assigns.user_color,
                   user_name: socket.assigns.user_name,
                   image_data: valid_result.data_url,
                   content_type: valid_result.content_type,
                   file_size: valid_result.file_size,
                   room_id: room.id
                 },
                 room.code
               ) do
            {:ok, photo} ->
              photo_with_type =
                photo
                |> Map.put(:type, :photo)
                |> Map.put(:unique_id, "photo-#{photo.id}")
                |> Map.put(:thumbnail_data, photo.thumbnail_data)

              {:noreply,
               socket
               |> assign(:uploading, false)
               |> assign(:item_count, socket.assigns.item_count + 1)
               |> assign(:photo_order, merge_photo_order(socket.assigns.photo_order, [photo.id], :front))
               |> stream_insert(:items, photo_with_type, at: 0)
               |> push_event("photo_uploaded", %{photo_id: photo.id})}

            {:error, _} ->
              {:noreply, socket |> assign(:uploading, false) |> put_flash(:error, "Upload failed")}
          end
      end
    end
  end

  def handle_progress(:photo, _entry, socket) do
    {:noreply, assign(socket, :uploading, true)}
  end

  # --- PubSub Handlers ---

  # Handle real-time room creation (e.g., when a friendship creates a DM room)
  def handle_info({:room_created, _room}, socket) do
    case socket.assigns.current_user do
      nil -> 
        {:noreply, socket}
      user ->
        private_rooms = Social.list_user_rooms(user.id)
        {:noreply, assign(socket, :user_private_rooms, private_rooms)}
    end
  end

  # Handle real-time public room creation (for all users to see new public rooms)
  def handle_info({:public_room_created, _room}, socket) do
    public_rooms = Social.list_public_rooms()
    {:noreply, assign(socket, :public_rooms, public_rooms)}
  end

  def handle_info({:new_photo, photo}, socket) do
    if photo.user_id != socket.assigns.user_id do
      photo_with_type =
        photo
        |> Map.put(:type, :photo)
        |> Map.put(:unique_id, "photo-#{photo.id}")
        |> Map.put(:thumbnail_data, photo.thumbnail_data)

      {:noreply,
       socket
       |> assign(:item_count, socket.assigns.item_count + 1)
       |> assign(:photo_order, merge_photo_order(socket.assigns.photo_order, [photo.id], :front))
       |> stream_insert(:items, photo_with_type, at: 0)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:photo_deleted, %{id: id}}, socket) do
    {:noreply,
     socket
     |> assign(:item_count, max(0, socket.assigns.item_count - 1))
     |> assign(:photo_order, remove_photo_from_order(socket.assigns.photo_order, id))
     |> stream_delete(:items, %{id: id, unique_id: "photo-#{id}"})}
  end

  def handle_info({:photo_thumbnail_updated, %{id: photo_id, thumbnail_data: thumbnail_data}}, socket) do
    # Update the stream with the new thumbnail using stream_insert
    case Social.get_photo(photo_id) do
      nil ->
        {:noreply, socket}

      photo ->
        photo_with_type =
          photo
          |> Map.from_struct()
          |> Map.put(:type, :photo)
          |> Map.put(:unique_id, "photo-#{photo.id}")
          |> Map.put(:thumbnail_data, thumbnail_data)

        {:noreply, stream_insert(socket, :items, photo_with_type)}
    end
  end

  def handle_info({:new_note, note}, socket) do
    if note.user_id != socket.assigns.user_id do
      note_with_type = note |> Map.put(:type, :note) |> Map.put(:unique_id, "note-#{note.id}")

      {:noreply,
       socket
       |> assign(:item_count, socket.assigns.item_count + 1)
       |> stream_insert(:items, note_with_type, at: 0)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:note_deleted, %{id: id}}, socket) do
    {:noreply,
     socket
     |> assign(:item_count, max(0, socket.assigns.item_count - 1))
     |> stream_delete(:items, %{id: id, unique_id: "note-#{id}"})}
  end

  def handle_info(%{event: "presence_diff", payload: %{joins: joins, leaves: leaves}}, socket) do
    # Efficiently update viewers without refetching entire list
    current_viewers = socket.assigns.viewers

    # Extract user info from joins
    new_users =
      joins
      |> Enum.map(fn {_user_id, %{metas: [meta | _]}} -> meta end)

    # Get user_ids from leaves
    left_user_ids =
      leaves
      |> Enum.map(fn {user_id, _} -> user_id end)
      |> MapSet.new()

    # Remove left users and add new users
    updated_viewers =
      current_viewers
      |> Enum.reject(fn viewer -> MapSet.member?(left_user_ids, viewer.user_id) end)
      |> Enum.concat(new_users)
      |> Enum.uniq_by(& &1.user_id)

    {:noreply, assign(socket, :viewers, updated_viewers)}
  end

  # Ignore task failure messages we don't explicitly handle
  def handle_info({_ref, :error}, socket), do: {:noreply, socket}
  # Ignore task DOWN messages (e.g., async thumbnail generation)
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket), do: {:noreply, socket}

  # --- Helpers ---

  defp generate_session_id, do: :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)

  defp generate_user_color(user_id) do
    hash = :crypto.hash(:md5, user_id)
    <<r, g, b, _::binary>> = hash
    "rgb(#{rem(r, 156) + 100}, #{rem(g, 156) + 100}, #{rem(b, 156) + 100})"
  end

  defp current_user_id(%{assigns: %{current_user: %{id: id}}}), do: id
  defp current_user_id(_), do: nil

  defp maybe_allow_upload(socket, true) do
    allow_upload(socket, :photo,
      accept: ~w(.jpg .jpeg .png .gif .webp),
      max_entries: 1,
      max_file_size: 10_000_000,
      auto_upload: true,
      progress: &handle_progress/3
    )
  end

  defp maybe_allow_upload(socket, _), do: socket

  defp photo_ids(items) do
    items
    |> Enum.filter(&(Map.get(&1, :type) == :photo))
    |> Enum.map(& &1.id)
  end

  defp merge_photo_order(order, ids, position) do
    order = order || []
    ids = ids |> Enum.reject(&is_nil/1) |> Enum.uniq()
    remaining = Enum.reject(order, &(&1 in ids))

    case position do
      :front -> ids ++ remaining
      :back -> remaining ++ ids
      _ -> remaining
    end
  end

  defp ensure_photo_in_order(order, id) do
    order = order || []

    cond do
      is_nil(id) -> order
      Enum.member?(order, id) -> order
      true -> order ++ [id]
    end
  end

  # Safe integer parsing to prevent crashes on invalid input
  defp safe_to_integer(value) when is_integer(value), do: {:ok, value}

  defp safe_to_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {num, ""} -> {:ok, num}
      _ -> {:error, :invalid_integer}
    end
  end

  defp safe_to_integer(_), do: {:error, :invalid_integer}

  defp normalize_photo_id(photo_id) when is_integer(photo_id), do: photo_id

  defp normalize_photo_id(photo_id) when is_binary(photo_id) do
    case safe_to_integer(photo_id) do
      {:ok, id} -> id
      {:error, _} -> nil
    end
  end

  defp normalize_photo_id(_), do: nil

  defp remove_photo_from_order(order, id) do
    order = order || []
    normalized = normalize_photo_id(id)
    Enum.reject(order, &(&1 == normalized))
  end

  defp maybe_close_deleted_photo(socket, photo_id) do
    if socket.assigns.current_photo_id == photo_id do
      socket
      |> assign(:show_image_modal, false)
      |> assign(:full_image_data, nil)
      |> assign(:current_photo_id, nil)
    else
      socket
    end
  end

  defp load_photo_into_modal(socket, photo_id) do
    photo_id_int = normalize_photo_id(photo_id)

    case photo_id_int do
      nil ->
        put_flash(socket, :error, "Invalid photo")

      _ ->
        case Social.get_photo(photo_id_int) do
          nil ->
            put_flash(socket, :error, "Could not load image")

          photo ->
            # Check if user can access the photo's room (security: prevent unauthorized access)
            photo_room = Social.get_room(photo.room_id)
            current_user_id = case socket.assigns.current_user do
              nil -> nil
              user -> user.id
            end

            if photo_room && Social.can_access_room?(photo_room, current_user_id) do
              raw = photo.image_data || photo.thumbnail_data
              content_type = photo.content_type || "image/jpeg"

              src =
                cond do
                  is_nil(raw) -> nil
                  String.starts_with?(raw, "data:") -> raw
                  true -> "data:#{content_type};base64,#{raw}"
                end

              if is_nil(src) do
                put_flash(socket, :error, "Could not load image")
              else
                base_order = current_photo_order(socket)
                order = ensure_photo_in_order(base_order, photo_id_int)
                current_idx = Enum.find_index(order, &(&1 == photo_id_int))

                socket
                |> assign(:show_image_modal, true)
                |> assign(:full_image_data, %{data: src, content_type: content_type, photo_id: photo.id, user_id: photo.user_id})
                |> assign(:photo_order, order)
                |> assign(:current_photo_id, photo_id_int)
                |> assign(:current_photo_index, current_idx)
              end
            else
              put_flash(socket, :error, "Access denied")
            end
        end
    end
  end

  defp navigate_photo(socket, direction) do
    base_order = current_photo_order(socket)
    order = ensure_photo_in_order(base_order, socket.assigns.current_photo_id)
    current = socket.assigns.current_photo_id

    cond do
      current == nil -> socket
      order == [] -> socket
      true ->
        idx = Enum.find_index(order, &(&1 == current)) || 0
        len = length(order)

        new_idx =
          case direction do
            :next -> rem(idx + 1, len)
            :prev -> rem(idx - 1 + len, len)
            _ -> idx
          end

        new_id = Enum.at(order, new_idx)
        load_photo_into_modal(socket, new_id)
    end
  end

  defp current_photo_order(socket) do
    case socket.assigns[:photo_order] do
      list when is_list(list) -> list
      _ -> []
    end
  end

  defp maybe_bootstrap_identity(%{assigns: %{user_id: user_id}} = socket, _params) when not is_nil(user_id),
    do: socket

  defp maybe_bootstrap_identity(socket, %{"browser_id" => browser_id} = params) do
    room = socket.assigns.room
    fingerprint = params["fingerprint"] || browser_id

    with {:ok, device, _} <- Social.register_device(fingerprint, browser_id),
         user_id when not is_nil(user_id) <- device.user_id,
         user when not is_nil(user) <- Social.get_user(user_id) do
      color = Enum.at(@colors, rem(user.id, length(@colors)))
      tracked_user_id = "user-#{user.id}"
      user_name = user.display_name || user.username

      viewers =
        if connected?(socket) do
          Presence.track_user(self(), room.code, tracked_user_id, color, user_name)
          Presence.list_users(room.code)
        else
          socket.assigns.viewers
        end

      private_rooms = if connected?(socket), do: Social.list_user_rooms(user.id), else: []

      socket
      |> assign(:current_user, user)
      |> assign(:pending_auth, nil)
      |> assign(:user_id, tracked_user_id)
      |> assign(:user_color, color)
      |> assign(:user_name, user_name)
      |> assign(:browser_id, browser_id)
      |> assign(:fingerprint, fingerprint)
      |> assign(:viewers, viewers)
      |> assign(:invites, Social.list_user_invites(user.id))
      |> assign(:trusted_friends, Social.list_trusted_friends(user.id))
      |> assign(:outgoing_trust_requests, Social.list_sent_trust_requests(user.id))
      |> assign(:pending_requests, Social.list_pending_trust_requests(user.id))
      |> assign(:recovery_requests, Social.list_recovery_requests_for_voter(user.id))
      |> assign(:user_private_rooms, private_rooms)
      |> assign(:room_access_denied, not Social.can_access_room?(room, user.id))
    else
      _ -> socket
    end
  end

  defp maybe_bootstrap_identity(socket, _), do: socket

  defp trusted_user_color(%{id: id}), do: color_from_user_id(id)
  defp trusted_user_color(_), do: "#666"

  defp color_from_user_id("user-" <> id_str) do
    case Integer.parse(id_str) do
      {int, ""} -> color_from_user_id(int)
      _ -> generate_user_color(id_str)
    end
  end

  defp color_from_user_id(user_id) when is_integer(user_id) do
    Enum.at(@colors, rem(user_id, length(@colors)))
  end

  defp color_from_user_id(user_id) when is_binary(user_id), do: generate_user_color(user_id)
  defp color_from_user_id(_), do: "#666"

  defp build_items(photos, notes) do
    photo_items = Enum.map(photos, fn p ->
      p
      |> Map.put(:type, :photo)
      |> Map.put(:unique_id, "photo-#{p.id}")
    end)
    
    note_items = Enum.map(notes, fn n ->
      n
      |> Map.put(:type, :note)
      |> Map.put(:unique_id, "note-#{n.id}")
    end)

    (photo_items ++ note_items)
    |> Enum.sort_by(fn item ->
      timestamp = Map.get(item, :uploaded_at) || Map.get(item, :inserted_at)

      case timestamp do
        %DateTime{} -> DateTime.to_unix(timestamp)
        %NaiveDateTime{} -> NaiveDateTime.diff(timestamp, ~N[1970-01-01 00:00:00])
        _ -> 0
      end
    end, :desc)
  end

  defp format_time(datetime) do
    now = DateTime.utc_now()

    datetime =
      case datetime do
        %NaiveDateTime{} -> DateTime.from_naive!(datetime, "Etc/UTC")
        %DateTime{} -> datetime
        _ -> DateTime.utc_now()
      end

    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "now"
      diff < 3600 -> "#{div(diff, 60)}m"
      diff < 86400 -> "#{div(diff, 3600)}h"
      true -> "#{div(diff, 86400)}d"
    end
  end

  defp format_voice_duration(ms) when is_integer(ms) do
    seconds = div(ms, 1000)
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)
    "#{minutes}:#{String.pad_leading(to_string(secs), 2, "0")}"
  end
  defp format_voice_duration(_), do: "0:00"
end
