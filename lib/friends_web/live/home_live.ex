defmodule FriendsWeb.HomeLive do
  use FriendsWeb, :live_view

  alias Friends.Social
  alias Friends.Social.Presence
  alias Friends.Repo
  import FriendsWeb.HomeLive.Helpers
  import FriendsWeb.HomeLive.Components.FeedComponents
  import FriendsWeb.HomeLive.Components.RoomComponents
  import FriendsWeb.HomeLive.Components.ModalComponents
  import FriendsWeb.HomeLive.Components.ChatComponents
  alias FriendsWeb.HomeLive.Events.FeedEvents
  alias FriendsWeb.HomeLive.Events.PhotoEvents
  alias FriendsWeb.HomeLive.Events.RoomEvents
  alias FriendsWeb.HomeLive.Events.NoteEvents
  alias FriendsWeb.HomeLive.Events.NetworkEvents
  alias FriendsWeb.HomeLive.Events.SettingsEvents
  alias FriendsWeb.HomeLive.PubSubHandlers
  import Ecto.Query
  require Logger

  @initial_batch 20
  @colors colors()

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
      # Subscribe to public feed updates
      Social.subscribe_to_public_feed(session_user.id)
    end

    # Load initial public feed items and contacts
    {feed_items, friends} =
      if session_user do
        items = Social.list_public_feed_items(session_user.id, 20)
        friends_list = Social.list_friends(session_user.id)
        {items, friends_list}
      else
        {[], []}
      end

    socket =
      socket
      |> assign(:session_id, session_id)
      # No specific room
      |> assign(:room, nil)
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
      |> assign(
        :user_rooms,
        if(session_user, do: Social.list_user_rooms(session_user.id), else: [])
      )
      |> assign(:dashboard_tab, "contacts")
      |> assign(:create_group_modal, false)
      |> assign(:new_room_name, "")
      |> assign(:join_code, "")
      |> assign(:current_route, "/")
      |> assign(:show_header_dropdown, false)
      # Required for layout to not crash
      |> assign(:room_access_denied, false)
      |> assign(:feed_mode, "dashboard")
      # Public feed assigns
      |> assign(:friends, friends)
      |> assign(:contacts_collapsed, false)
      |> assign(:groups_collapsed, false)
      |> assign(:note_input, "")
      |> assign(:recording_voice, false)
      |> assign(:uploading, false)
      |> assign(:show_image_modal, false)
      |> assign(:full_image_data, nil)
      |> assign(:feed_item_count, length(feed_items))
      |> stream(:feed_items, feed_items, dom_id: &"feed-item-#{&1.type}-#{&1.id}")

    # Allow uploads for the public feed
    socket =
      if session_user do
        allow_upload(socket, :feed_photo,
          accept: ~w(.jpg .jpeg .png .gif .webp),
          max_entries: 1,
          max_file_size: 20_000_000,
          auto_upload: true,
          progress: &handle_progress/3
        )
      else
        socket
      end

    socket = maybe_bootstrap_identity(socket, get_connect_params(socket))

    {:ok, socket}
  end

  defp load_session_user(session) do
    case session["user_id"] do
      nil ->
        {nil, nil, nil, nil}

      user_id ->
        case Social.get_user(user_id) do
          nil ->
            {nil, nil, nil, nil}

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

        r ->
          r
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

        if room.is_private do
          Social.subscribe_to_room_chat(room.id)
        end

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
        # "content" or "chat"
        |> assign(:room_tab, "content")
        |> assign(
          :room_messages,
          if(room.is_private and can_access, do: Social.list_room_messages(room.id, 50), else: [])
        )
        |> assign(:new_chat_message, "")
        |> assign(:recording_voice, false)
        # Collapsible chat panel, default open for private
        |> assign(:show_chat_panel, room.is_private)
        |> assign(:show_mobile_chat, false)
        |> assign(:show_room_modal, false)
        |> assign(:show_name_modal, false)
        |> assign(:show_note_modal, false)
        |> assign(:show_settings_modal, false)
        |> assign(:show_network_modal, false)
        |> assign(:settings_tab, "profile")
        |> assign(:network_tab, "friends")
        |> assign(:note_input, "")
        |> assign(:viewing_note, nil)
        |> assign(:join_code, "")
        |> assign(:new_room_name, "")
        |> assign(:create_private_room, false)
        |> assign(:create_group_modal, false)
        |> assign(:name_input, "")
        |> assign(:uploading, false)
        |> assign(:invites, [])
        |> assign(:trusted_friends, [])
        |> assign(:outgoing_trust_requests, [])
        |> assign(
          :pending_requests,
          if(session_user, do: Social.list_friend_requests(session_user.id), else: [])
        )
        |> assign(:friend_search, "")
        |> assign(:friend_search_results, [])
        |> assign(:recovery_requests, [])
        |> assign(
          :room_members,
          if(room.is_private and can_access, do: Social.list_room_members(room.id), else: [])
        )
        |> assign(:member_invite_search, "")
        |> assign(:member_invite_results, [])
        |> assign(
          :user_private_rooms,
          if(session_user, do: Social.list_user_rooms(session_user.id), else: [])
        )
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
        |> stream(:items, items, dom_id: &"item-#{&1.unique_id}")
        |> maybe_allow_upload(can_access)

      socket = maybe_bootstrap_identity(socket, get_connect_params(socket))

      {:ok, socket}
    end
  end

  def handle_params(%{"room" => room_code}, _uri, socket) do
    current_room_code = socket.assigns[:room] && socket.assigns.room.code

    if current_room_code != room_code do
      old_room = socket.assigns[:room]

      # Only cleanup subscriptions if coming from another room
      if old_room do
        if socket.assigns.user_id do
          Presence.untrack(self(), old_room.code, socket.assigns.user_id)
        end

        Social.unsubscribe(old_room.code)
        Phoenix.PubSub.unsubscribe(Friends.PubSub, "friends:presence:#{old_room.code}")
      end

      room =
        case Social.get_room_by_code(room_code) do
          nil -> Social.get_or_create_public_square()
          r -> r
        end

      can_access = Social.can_access_room?(room, current_user_id(socket))

      if can_access do
        Social.subscribe(room.code)
        Phoenix.PubSub.subscribe(Friends.PubSub, "friends:presence:#{room.code}")

        if room.is_private do
          Social.subscribe_to_room_chat(room.id)
        end

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
      private_rooms =
        case socket.assigns.current_user do
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
       |> assign(:show_chat_panel, room.is_private)
       |> assign(
         :room_messages,
         if(room.is_private and can_access, do: Social.list_room_messages(room.id, 50), else: [])
       )
       |> assign(:photo_order, if(can_access, do: photo_ids(items), else: []))
       |> assign(:user_private_rooms, private_rooms)
       |> assign(:public_rooms, public_rooms)
       |> assign(:feed_mode, "room")
       |> assign(:recording_voice, false)
       |> assign(:uploading, false)
       |> assign(:show_chat_panel, room.is_private)
       |> assign(:current_route, "/r/#{room.code}")
       |> assign(
         :room_members,
         if(room.is_private and can_access, do: Social.list_room_members(room.id), else: [])
       )
       |> maybe_allow_upload(can_access)
       |> stream(:items, items, reset: true, dom_id: &"item-#{&1.unique_id}")}
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
    user_rooms =
      if socket.assigns.current_user do
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
     |> assign(:current_route, "/")}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  def render(assigns) do
    ~H"""
    <div class="text-neutral-200 font-sans selection:bg-neutral-700 selection:text-white pb-20">
      <.photo_modal show={assigns[:show_image_modal]} photo={assigns[:full_image_data]} />
      <.note_modal show={assigns[:show_note_modal]} action={assigns[:note_modal_action]} />
      <%= if @live_action == :index do %>
        <%!-- Dashboard View --%>
        <div class="max-w-[1600px] mx-auto p-4 sm:p-8">
          <%= if @current_user do %>
            <div id="public-feed-app" class="flex flex-col lg:flex-row gap-6" phx-hook="FriendsApp">
              <%!-- Main Feed Area --%>
              <div class="flex-1 min-w-0">
                <%!-- Post Actions Bar --%>
                <%!-- Upload progress --%>
                <.feed_upload_progress uploads={assigns[:uploads]} />
                <.feed_actions_bar
                  uploads={assigns[:uploads]}
                  uploading={@uploading}
                  recording_voice={@recording_voice}
                /> <%!-- Feed Grid --%>
                <%= if @feed_item_count == 0 do %>
                  <.empty_feed />
                <% else %>
                  <.feed_grid feed_items={@streams.feed_items} />
                <% end %>
              </div>
               <.sidebar users={@friends} rooms={@user_rooms} new_room_name={@new_room_name} />
            </div>
          <% else %>
            <%!-- Guests Landing --%>
            <div class="max-w-md mx-auto mt-20 text-center">
              <h1 class="text-4xl md:text-5xl font-bold mb-4 bg-clip-text text-transparent bg-gradient-to-br from-white to-neutral-500">
                Friends
              </h1>
              
              <p class="text-neutral-400 text-lg mb-8">Simple, secure, and private messaging.</p>
              
              <div class="flex flex-col gap-3">
                <a
                  href="/login"
                  class="w-full py-3 rounded-xl glass border border-white/10 hover:bg-white/10 transition-colors text-white font-medium"
                >
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
        <div
          id="friends-app"
          class="text-white relative"
          phx-hook="FriendsApp"
          phx-window-keydown="handle_keydown"
        >
          <%!-- Main content - wider and more spacious --%>
          <div class="max-w-[1600px] mx-auto px-8 pt-10 pb-4">
            <%!-- Network Info (when in network mode) --%>
            <.network_info_card
              feed_mode={@feed_mode}
              current_user={@current_user}
              trusted_friends={@trusted_friends}
              outgoing_trust_requests={@outgoing_trust_requests}
            /> <%!-- Main split-view layout container --%>
            <div class={if @room.is_private and not @room_access_denied, do: "", else: ""}>
              <%!-- Left: Main content area (with right margin for fixed chat on lg screens) --%>
              <div class={
                if @room.is_private and not @room_access_denied, do: "lg:mr-[400px]", else: ""
              }>
                <%!-- Upload progress --%> <.upload_progress uploads={assigns[:uploads]} />
                <%!-- Access Denied for Private Rooms --%>
                <.access_denied
                  room_access_denied={@room_access_denied}
                  room={@room}
                  current_user={@current_user}
                /> <%!-- Content grid --%>
                <.empty_room
                  item_count={@item_count}
                  current_user={@current_user}
                  room_access_denied={@room_access_denied}
                  feed_mode={@feed_mode}
                  network_filter={@network_filter}
                />
                <.invite_modal
                  show={assigns[:show_invite_modal]}
                  room={@room}
                  invite_username={@room_invite_username}
                />
                <.mobile_action_bar
                  current_user={@current_user}
                  room_access_denied={@room_access_denied}
                  uploads={assigns[:uploads]}
                  uploading={@uploading}
                  recording_voice={@recording_voice}
                  room={@room}
                />
                <.desktop_action_cards
                  current_user={@current_user}
                  room_access_denied={@room_access_denied}
                  uploads={assigns[:uploads]}
                  uploading={@uploading}
                  recording_voice={@recording_voice}
                  room={@room}
                /> <.room_grid items={@streams.items} room={@room} current_user={@current_user} />
                <.load_more_button no_more_items={@no_more_items} />
              </div>
              <%!-- Close left content wrapper --%>
              <%!-- Right: Chat Panel (always visible for private spaces) --%>
              <%= if @room.is_private and not @room_access_denied and @current_user do %>
                <.chat_panel
                  room={@room}
                  current_user={@current_user}
                  room_members={@room_members}
                  room_messages={@room_messages}
                  new_chat_message={@new_chat_message}
                  show_mobile_chat={@show_mobile_chat}
                /> <.mobile_chat_toggle show_mobile_chat={@show_mobile_chat} />
              <% end %>
            </div>
            <%!-- Close flex container --%>
          </div>
           <%!-- Room Modal --%>
          <%= if @show_room_modal do %>
            <div
              id="room-modal-overlay"
              class="fixed inset-0 z-50 flex items-end sm:items-center justify-center p-4 modal-backdrop animate-in fade-in duration-200"
              phx-click-away="close_room_modal"
              role="dialog"
              aria-modal="true"
              aria-labelledby="room-modal-title"
              phx-hook="LockScroll"
            >
              <div class="w-full sm:max-w-md opal-card opal-prismatic sm:rounded-2xl rounded-t-2xl shadow-2xl max-h-[85vh] flex flex-col animate-in zoom-in-95 duration-200">
                <%!-- Header --%>
                <div class="p-6 border-b border-white/5 opal-aurora shrink-0">
                  <div class="flex items-center justify-between">
                    <div>
                      <h2 id="room-modal-title" class="text-xl font-semibold text-white">Groups</h2>
                      
                      <p class="text-sm text-neutral-400 mt-1">Switch to another group</p>
                    </div>
                    
                    <button
                      type="button"
                      phx-click="close_room_modal"
                      class="w-10 h-10 flex items-center justify-center text-neutral-400 hover:text-white hover:bg-white/10 rounded-xl transition-all cursor-pointer"
                      aria-label="Close"
                    >
                      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M6 18L18 6M6 6l12 12"
                        />
                      </svg>
                    </button>
                  </div>
                </div>
                 <%!-- Content - scrollable --%>
                <div class="flex-1 overflow-y-auto p-4 space-y-4">
                  <%= if @room.is_private && @current_user do %>
                    <div class="p-4 bg-neutral-800/50 rounded-xl space-y-3">
                      <div class="text-xs text-neutral-500 uppercase tracking-wider">
                        Invite people
                      </div>
                      
                      <p class="text-sm text-neutral-300">
                        Share this code or link so trusted people can join your private space.
                      </p>
                      
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
                      
                      <p class="text-xs text-neutral-500">
                        Only members can access private spaces. Share wisely.
                      </p>
                      
                      <%= if @room.owner_id == @current_user.id do %>
                        <div class="pt-2 space-y-2">
                          <div class="text-xs text-neutral-500 uppercase tracking-wider">
                            Add member by username
                          </div>
                          
                          <form
                            phx-submit="add_room_member"
                            phx-change="update_room_invite_username"
                            class="flex gap-2"
                          >
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
                        <span class="text-xs text-neutral-500 uppercase tracking-wider">
                          Your Private Spaces
                        </span>
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
                              room.code == @room.code &&
                                "bg-green-500/20 border border-green-500/30 ring-1 ring-green-500/20",
                              room.code != @room.code &&
                                "bg-neutral-800/50 hover:bg-neutral-800 border border-transparent"
                            ]}
                          >
                            <div class="w-8 h-8 bg-green-500/20 rounded-lg flex items-center justify-center">
                              <span class="text-sm">🔒</span>
                            </div>
                            
                            <span class={[
                              "font-medium truncate",
                              room.code == @room.code && "text-green-400",
                              room.code != @room.code && "text-neutral-300"
                            ]}>
                              {room.name || room.code}
                            </span>
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
                    <button
                      type="submit"
                      phx-disable-with="..."
                      class="w-24 px-5 py-3 bg-white text-black text-sm font-medium rounded-xl hover:bg-neutral-200 transition-colors disabled:opacity-50 cursor-pointer"
                    >
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
                      <button
                        type="submit"
                        phx-disable-with="..."
                        class="w-24 px-5 py-3 border border-neutral-600 text-neutral-300 text-sm font-medium rounded-xl hover:border-neutral-500 hover:text-white hover:bg-neutral-800 transition-all disabled:opacity-50 cursor-pointer"
                      >
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
              <div class="w-full max-w-md opal-card opal-prismatic rounded-2xl shadow-2xl overflow-hidden animate-in zoom-in-95 duration-200">
                <%!-- Header with aurora gradient --%>
                <div class="p-6 border-b border-white/5 opal-aurora">
                  <div class="flex items-center justify-between">
                    <div>
                      <h2 id="create-group-modal-title" class="text-xl font-semibold text-white">
                        Create Group
                      </h2>
                      
                      <p class="text-sm text-neutral-400 mt-1">
                        Start a private space for your friends
                      </p>
                    </div>
                    
                    <button
                      type="button"
                      phx-click="close_create_group_modal"
                      class="w-10 h-10 flex items-center justify-center text-neutral-400 hover:text-white hover:bg-white/10 rounded-xl transition-all cursor-pointer"
                      aria-label="Close"
                    >
                      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M6 18L18 6M6 6l12 12"
                        />
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
                      class="w-full px-4 py-3 opal-input text-white placeholder:text-neutral-600 focus:outline-none transition-all"
                    />
                    <p class="text-xs text-neutral-600 mt-2">
                      Leave empty for an auto-generated code name
                    </p>
                  </div>
                  
                  <div class="flex gap-3">
                    <button
                      type="button"
                      phx-click="close_create_group_modal"
                      class="flex-1 px-4 py-3 btn-opal-secondary cursor-pointer"
                    >
                      Cancel
                    </button>
                    <button
                      type="submit"
                      phx-disable-with="Creating..."
                      class="flex-1 btn-opal-primary cursor-pointer"
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
                        
                        <p>
                          Only people you invite can access your group. Share the link or add members directly.
                        </p>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          <% end %>
          
          <%= if @show_invite_modal do %>
            <div
              id="invite-modal-overlay"
              class="fixed inset-0 z-50 flex items-center justify-center p-4 modal-backdrop animate-in fade-in duration-200"
              phx-click-away="close_invite_modal"
              role="dialog"
              aria-modal="true"
              phx-hook="LockScroll"
            >
              <div class="w-full max-w-md opal-card opal-prismatic rounded-2xl shadow-2xl overflow-hidden animate-in zoom-in-95 duration-200">
                <%!-- Header --%>
                <div class="p-6 border-b border-white/5 opal-aurora">
                  <div class="flex items-center justify-between">
                    <div>
                      <h2 class="text-xl font-semibold text-white">Invite People</h2>
                      
                      <p class="text-sm text-neutral-400 mt-1">Add friends to this space</p>
                    </div>
                    
                    <button
                      type="button"
                      phx-click="close_invite_modal"
                      class="w-10 h-10 flex items-center justify-center text-neutral-400 hover:text-white hover:bg-white/10 rounded-xl transition-all cursor-pointer"
                    >
                      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M6 18L18 6M6 6l12 12"
                        />
                      </svg>
                    </button>
                  </div>
                </div>
                
                <div class="p-6 space-y-6">
                  <%= if @room.is_private do %>
                    <div class="space-y-3">
                      <label class="text-xs font-semibold text-neutral-500 uppercase tracking-wider">
                        Share Link
                      </label>
                      <div class="flex gap-2">
                        <input
                          type="text"
                          value={url(~p"/r/#{@room.code}")}
                          readonly
                          class="flex-1 px-4 py-3 bg-neutral-950/50 opal-input border border-white/10 rounded-xl text-sm text-neutral-300 font-mono select-all focus:outline-none"
                        />
                        <button
                          phx-hook="CopyToClipboard"
                          data-copy={url(~p"/r/#{@room.code}")}
                          id="copy-invite-link-modal"
                          class="px-4 py-3 bg-white text-black text-sm font-medium rounded-xl hover:bg-neutral-200 transition-colors cursor-pointer"
                        >
                          Copy
                        </button>
                      </div>
                    </div>
                    
                    <div class="relative flex items-center gap-4 py-2">
                      <div class="flex-1 border-t border-white/10"></div>
                       <span class="text-xs text-neutral-500 uppercase">OR</span>
                      <div class="flex-1 border-t border-white/10"></div>
                    </div>
                  <% end %>
                  
                  <div class="space-y-3">
                    <label class="text-xs font-semibold text-neutral-500 uppercase tracking-wider">
                      Add Member
                    </label>
                    <form phx-change="search_member_invite" phx-submit="search_member_invite">
                      <div class="relative">
                        <svg
                          class="absolute left-4 top-1/2 -translate-y-1/2 w-4 h-4 text-neutral-500"
                          fill="none"
                          stroke="currentColor"
                          viewBox="0 0 24 24"
                        >
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            stroke-width="2"
                            d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"
                          />
                        </svg>
                        <input
                          type="text"
                          name="query"
                          value={@member_invite_search}
                          placeholder="Search by username..."
                          class="w-full pl-10 pr-4 py-3 bg-neutral-950/50 opal-input border border-white/10 rounded-xl text-sm text-white placeholder:text-neutral-600 focus:outline-none focus:border-white/20 transition-all"
                          autocomplete="off"
                          phx-debounce="300"
                        />
                      </div>
                    </form>
                    
                    <%= if @member_invite_results != [] do %>
                      <div class="mt-2 max-h-48 overflow-y-auto space-y-1 pr-1 custom-scrollbar">
                        <%= for user <- @member_invite_results do %>
                          <div class="flex items-center justify-between p-3 hover:bg-white/5 rounded-xl group transition-colors border border-transparent hover:border-white/5">
                            <div class="flex items-center gap-3">
                              <div
                                class="w-8 h-8 rounded-full flex items-center justify-center text-xs font-bold text-black"
                                style={"background-color: #{trusted_user_color(user)}"}
                              >
                                {String.first(user.username) |> String.upcase()}
                              </div>
                              
                              <span class="text-sm text-neutral-300 font-medium group-hover:text-white transition-colors">
                                @{user.username}
                              </span>
                            </div>
                            
                            <button
                              phx-click="invite_to_room"
                              phx-value-user_id={user.id}
                              class="text-xs font-medium text-emerald-400 hover:text-black px-3 py-1.5 bg-emerald-500/10 hover:bg-emerald-400 rounded-lg transition-all cursor-pointer"
                            >
                              Invite
                            </button>
                          </div>
                        <% end %>
                      </div>
                    <% else %>
                      <%= if @member_invite_search != "" do %>
                        <div class="text-center py-4 text-neutral-500 text-sm">No users found</div>
                      <% end %>
                    <% end %>
                  </div>
                </div>
              </div>
            </div>
          <% end %>
           <%!-- Name Modal --%>
          <%= if @show_name_modal do %>
            <div
              class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80"
              phx-click-away="close_name_modal"
            >
              <div class="w-full max-w-sm bg-neutral-900 border border-neutral-800 p-6">
                <div class="flex items-center justify-between mb-6">
                  <h2 class="text-sm font-medium">identity</h2>
                  
                  <button
                    type="button"
                    phx-click="close_name_modal"
                    class="text-neutral-500 hover:text-white cursor-pointer"
                  >
                    ×
                  </button>
                </div>
                
                <div class="mb-6 flex items-center gap-3">
                  <div
                    class="w-8 h-8 rounded-full"
                    style={"background-color: #{@user_color || "#666"}"}
                  />
                  <div>
                    <div class="text-sm">{@user_name || "anonymous"}</div>
                    
                    <div class="text-xs text-neutral-600">
                      {if @user_id, do: String.slice(@user_id, 0, 12) <> "...", else: "..."}
                    </div>
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
                    <button
                      type="submit"
                      class="px-4 py-2 bg-white text-black text-sm hover:bg-neutral-200 cursor-pointer"
                    >
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
            <div
              id="note-modal-overlay"
              class="fixed inset-0 z-50 flex items-center justify-center p-4 modal-backdrop animate-in fade-in duration-200"
              phx-click-away="close_note_modal"
              phx-hook="LockScroll"
            >
              <div class="w-full max-w-md opal-card opal-prismatic rounded-2xl shadow-2xl overflow-hidden animate-in zoom-in-95 duration-200">
                <%!-- Header --%>
                <div class="p-6 border-b border-white/5 opal-aurora">
                  <div class="flex items-center justify-between">
                    <div>
                      <h2 class="text-xl font-semibold text-white">New Note</h2>
                      
                      <p class="text-sm text-neutral-400 mt-1">Share a thought with the group</p>
                    </div>
                    
                    <button
                      type="button"
                      phx-click="close_note_modal"
                      class="w-10 h-10 flex items-center justify-center text-neutral-400 hover:text-white hover:bg-white/10 rounded-xl transition-all cursor-pointer"
                      aria-label="Close"
                    >
                      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M6 18L18 6M6 6l12 12"
                        />
                      </svg>
                    </button>
                  </div>
                </div>
                
                <form phx-submit="save_note" phx-change="update_note" class="p-6">
                  <textarea
                    id="note-input"
                    name="content"
                    value={@note_input}
                    placeholder="What's on your mind?"
                    maxlength="500"
                    rows="5"
                    phx-hook="AutoFocus"
                    class="w-full p-4 opal-input text-base text-white placeholder:text-neutral-600 focus:outline-none resize-none mb-4"
                  >{@note_input}</textarea>
                  <div class="flex items-center justify-between">
                    <span class="text-xs text-neutral-500">{String.length(@note_input)}/500</span>
                    <button
                      type="submit"
                      disabled={String.trim(@note_input) == ""}
                      class="btn-opal-primary px-6 py-2.5 rounded-xl text-sm font-medium disabled:opacity-50 disabled:cursor-not-allowed cursor-pointer shadow-lg shadow-emerald-500/10 hover:shadow-emerald-500/20"
                    >
                      Share Note
                    </button>
                  </div>
                </form>
              </div>
            </div>
          <% end %>
           <%!-- View Full Note Modal --%>
          <%= if @viewing_note do %>
            <div
              id="view-note-modal-overlay"
              class="fixed inset-0 z-50 flex items-center justify-center p-4 modal-backdrop animate-in fade-in duration-200"
              phx-click-away="close_view_note"
              phx-hook="LockScroll"
            >
              <div class="w-full max-w-lg opal-card opal-prismatic rounded-2xl shadow-2xl overflow-hidden animate-in zoom-in-95 duration-200 max-h-[80vh] flex flex-col">
                <%!-- Header --%>
                <div class="p-4 border-b border-white/5 flex items-center justify-between shrink-0">
                  <div class="flex items-center gap-2 text-sm text-neutral-400">
                    <span>@{@viewing_note.user}</span> <span class="text-neutral-600">·</span>
                    <span class="text-neutral-600">{@viewing_note.time}</span>
                  </div>
                  
                  <button
                    type="button"
                    phx-click="close_view_note"
                    class="w-8 h-8 flex items-center justify-center text-neutral-400 hover:text-white hover:bg-white/10 rounded-lg transition-all cursor-pointer"
                    aria-label="Close"
                  >
                    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M6 18L18 6M6 6l12 12"
                      />
                    </svg>
                  </button>
                </div>
                 <%!-- Content --%>
                <div class="p-6 overflow-y-auto flex-1">
                  <p class="text-base text-neutral-200 leading-relaxed whitespace-pre-wrap">
                    {@viewing_note.content}
                  </p>
                </div>
              </div>
            </div>
          <% end %>
           <%!-- Network Modal --%>
          <%= if @show_network_modal && @current_user do %>
            <div
              id="network-modal-overlay"
              class="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/80 backdrop-blur-sm"
              phx-click-away="close_network_modal"
              phx-hook="LockScroll"
            >
              <div class="w-full sm:max-w-md sm:mx-4 bg-neutral-950 sm:rounded-2xl max-h-[90vh] sm:max-h-[85vh] overflow-hidden flex flex-col rounded-t-2xl sm:border sm:border-white/10">
                <%!-- Header --%>
                <div class="relative px-5 pt-5 pb-4 border-b border-white/5">
                  <button
                    type="button"
                    phx-click="close_network_modal"
                    class="absolute top-4 right-4 w-8 h-8 flex items-center justify-center text-neutral-500 hover:text-white rounded-full hover:bg-white/10 transition-all cursor-pointer"
                  >
                    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M6 18L18 6M6 6l12 12"
                      />
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
                      <span class="text-sm font-medium text-violet-300 group-hover:text-violet-200">
                        Graph
                      </span>
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
                                    <div class="text-sm font-medium text-white">
                                      @{req.user.username}
                                    </div>
                                    
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
                            <svg
                              class="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-neutral-600"
                              fill="none"
                              stroke="currentColor"
                              viewBox="0 0 24 24"
                            >
                              <path
                                stroke-linecap="round"
                                stroke-linejoin="round"
                                stroke-width="2"
                                d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"
                              />
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
                              
                              <div class="text-xs text-neutral-600 mt-1">
                                Search above to add friends
                              </div>
                            </div>
                          <% else %>
                            <%= for tf <- @trusted_friends do %>
                              <div class="flex items-center gap-3 p-3 bg-neutral-950/50 rounded-xl border border-white/5">
                                <div class="w-9 h-9 rounded-full bg-green-500/20 flex items-center justify-center">
                                  <svg
                                    class="w-4 h-4 text-green-400"
                                    fill="none"
                                    stroke="currentColor"
                                    viewBox="0 0 24 24"
                                  >
                                    <path
                                      stroke-linecap="round"
                                      stroke-linejoin="round"
                                      stroke-width="2"
                                      d="M5 13l4 4L19 7"
                                    />
                                  </svg>
                                </div>
                                
                                <div class="flex-1">
                                  <div class="text-sm font-medium text-white">
                                    @{tf.trusted_user.username}
                                  </div>
                                  
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
                                  <div class="text-sm font-medium text-white">
                                    @{req.trusted_user.username}
                                  </div>
                                  
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
                            
                            <div class="text-xs text-neutral-600 mt-1">
                              Create one to invite friends
                            </div>
                          </div>
                        <% else %>
                          <%= for invite <- @invites do %>
                            <div class={[
                              "p-4 rounded-xl border transition-all",
                              invite.status == "active" && "bg-neutral-950/50 border-white/5",
                              invite.status == "used" &&
                                "bg-neutral-950/30 border-white/[0.02] opacity-60"
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
            <div
              id="settings-modal-overlay"
              class="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/80 backdrop-blur-sm"
              phx-click-away="close_settings_modal"
              phx-hook="LockScroll"
            >
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
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M6 18L18 6M6 6l12 12"
                      />
                    </svg>
                  </button> <%!-- Profile info --%>
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
                            <div class="text-sm font-medium text-white group-hover:text-blue-300 transition-colors">
                              Devices
                            </div>
                            
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
                            <div class="text-sm font-medium text-white group-hover:text-emerald-300 transition-colors">
                              Link
                            </div>
                            
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
                            <div class="text-sm font-medium text-white group-hover:text-amber-300 transition-colors">
                              Recover
                            </div>
                            
                            <div class="text-xs text-neutral-600">Lost access?</div>
                          </div>
                        </a>
                      </div>
                       <%!-- Recovery Requests (urgent) --%>
                      <%= if @recovery_requests != [] do %>
                        <div class="p-4 bg-red-500/10 rounded-xl border border-red-500/20">
                          <div class="flex items-center gap-2 mb-3">
                            <span class="text-red-400">🚨</span>
                            <span class="text-sm font-medium text-red-400">
                              Friends need help recovering
                            </span>
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
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            stroke-width="2"
                            d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1"
                          />
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
                          <div class="text-sm font-medium text-emerald-400">
                            {@room.name || @room.code}
                          </div>
                          
                          <div class="text-xs text-emerald-500/70">
                            Private room - {length(@room_members)} members
                          </div>
                        </div>
                      </div>
                       <%!-- Search to invite --%>
                      <div>
                        <div class="text-xs font-semibold text-neutral-500 uppercase tracking-wider mb-3">
                          Invite Members
                        </div>
                        
                        <form phx-change="search_member_invite">
                          <div class="relative">
                            <svg
                              class="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-neutral-600"
                              fill="none"
                              stroke="currentColor"
                              viewBox="0 0 24 24"
                            >
                              <path
                                stroke-linecap="round"
                                stroke-linejoin="round"
                                stroke-width="2"
                                d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"
                              />
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
                                  <svg
                                    class="w-4 h-4 text-amber-400"
                                    fill="currentColor"
                                    viewBox="0 0 20 20"
                                  >
                                    <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
                                  </svg>
                                <% end %>
                              </div>
                              
                              <div class="flex-1">
                                <div class="text-sm font-medium text-white">
                                  @{member.user.username}
                                </div>
                                
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
                                  <svg
                                    class="w-4 h-4"
                                    fill="none"
                                    stroke="currentColor"
                                    viewBox="0 0 24 24"
                                  >
                                    <path
                                      stroke-linecap="round"
                                      stroke-linejoin="round"
                                      stroke-width="2"
                                      d="M6 18L18 6M6 6l12 12"
                                    />
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
                class="absolute left-2 sm:left-6 top-1/2 -translate-y-1/2 w-11 h-11 flex items-center justify-center glass rounded-full text-white hover:text-neutral-300 cursor-pointer border border-white/10 hover:border-white/20 transition-all z-10"
                aria-label="Previous photo"
              >
                <svg
                  class="w-5 h-5"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2"
                  viewBox="0 0 24 24"
                >
                  <path stroke-linecap="round" stroke-linejoin="round" d="M15 19l-7-7 7-7" />
                </svg>
              </button>
              <div class="relative max-w-6xl max-h-[90vh] flex items-center justify-center">
                <button
                  type="button"
                  phx-click="close_image_modal"
                  class="absolute -top-12 sm:-top-14 right-0 w-11 h-11 flex items-center justify-center glass rounded-full text-white hover:text-neutral-300 cursor-pointer border border-white/10 hover:border-white/20 transition-all z-10"
                  aria-label="Close photo viewer"
                >
                  <svg
                    class="w-5 h-5"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    viewBox="0 0 24 24"
                  >
                    <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
                  </svg>
                </button>
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
                class="absolute right-2 sm:right-6 top-1/2 -translate-y-1/2 w-11 h-11 flex items-center justify-center glass rounded-full text-white hover:text-neutral-300 cursor-pointer border border-white/10 hover:border-white/20 transition-all z-10"
                aria-label="Next photo"
              >
                <svg
                  class="w-5 h-5"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2"
                  viewBox="0 0 24 24"
                >
                  <path stroke-linecap="round" stroke-linejoin="round" d="M9 5l7 7-7 7" />
                </svg>
              </button>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # --- Events ---

  def handle_event(
        "set_user_id",
        %{"browser_id" => browser_id, "fingerprint" => fingerprint},
        socket
      ) do
    room = socket.assigns.room

    # On dashboard (index), room is nil - just return early
    if is_nil(room) do
      {:noreply, socket}
    else
      set_user_id_for_room(socket, room, browser_id, fingerprint)
    end
  end

  defp set_user_id_for_room(socket, room, browser_id, fingerprint) do
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

  def handle_event("validate", _params, socket), do: PhotoEvents.validate(socket)
  def handle_event("save", _params, socket), do: PhotoEvents.save(socket)

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    PhotoEvents.cancel_upload(socket, ref)
  end

  def handle_event("delete_photo", %{"id" => id}, socket) do
    PhotoEvents.delete_photo(socket, id)
  end

  def handle_event("set_thumbnail", %{"photo_id" => photo_id, "thumbnail" => thumbnail}, socket) do
    PhotoEvents.set_thumbnail(socket, photo_id, thumbnail)
  end

  def handle_event("delete_note", %{"id" => id}, socket) do
    NoteEvents.delete_note(socket, id)
  end

  # Room events
  def handle_event("open_room_modal", _params, socket), do: RoomEvents.open_room_modal(socket)
  def handle_event("close_room_modal", _params, socket), do: RoomEvents.close_room_modal(socket)

  # Create Group modal events
  def handle_event("open_create_group_modal", _params, socket),
    do: RoomEvents.open_create_group_modal(socket)

  def handle_event("close_create_group_modal", _params, socket),
    do: RoomEvents.close_create_group_modal(socket)

  def handle_event("create_group", %{"name" => name}, socket) do
    RoomEvents.create_group(socket, name)
  end

  def handle_event("update_join_code", %{"code" => code}, socket) do
    RoomEvents.update_join_code(socket, code)
  end

  def handle_event("update_room_name", %{"name" => name}, socket) do
    {:noreply, assign(socket, :new_room_name, name)}
  end

  def handle_event("update_room_form", params, socket) do
    RoomEvents.update_room_form(socket, params)
  end

  # --- Public Feed Event Handlers ---

  def handle_event("toggle_contacts", _, socket) do
    FeedEvents.toggle_contacts(socket)
  end

  def handle_event("toggle_groups", _, socket) do
    FeedEvents.toggle_groups(socket)
  end

  def handle_event("validate_feed_photo", _, socket) do
    PhotoEvents.validate_feed_photo(socket)
  end

  def handle_event("open_feed_note_modal", _, socket) do
    {:noreply, assign(socket, :show_note_modal, true)}
  end

  def handle_event("close_note_modal", _, socket) do
    {:noreply, assign(socket, :show_note_modal, false)}
  end

  def handle_event("view_feed_photo", %{"photo_id" => photo_id}, socket) do
    PhotoEvents.view_feed_photo(socket, photo_id)
  end

  def handle_event("close_photo_modal", _, socket) do
    PhotoEvents.close_photo_modal(socket)
  end

  def handle_event("post_feed_note", %{"note" => content}, socket) do
    NoteEvents.post_feed_note(socket, content)
  end

  def handle_event("start_voice_recording", _, socket) do
    NoteEvents.start_voice_recording(socket)
  end

  def handle_event("post_public_voice", %{"audio_data" => _} = params, socket) do
    NoteEvents.post_public_voice(socket, params)
  end

  def handle_event("open_dm", %{"user_id" => friend_user_id}, socket) do
    RoomEvents.open_dm(socket, friend_user_id)
  end

  def handle_event("update_room_invite_username", %{"username" => username}, socket) do
    RoomEvents.update_room_invite_username(socket, username)
  end

  def handle_event("add_room_member", %{"username" => username}, socket) do
    RoomEvents.add_room_member(socket, username)
  end

  def handle_event("set_network_filter", %{"filter" => filter}, socket) do
    FeedEvents.set_network_filter(socket, filter)
  end

  def handle_event("join_room", %{"code" => code}, socket) do
    RoomEvents.join_room(socket, code)
  end

  def handle_event("create_room", params, socket) do
    RoomEvents.create_room(socket, params)
  end

  def handle_event("go_to_public_square", _params, socket) do
    RoomEvents.go_to_public_square(socket)
  end

  def handle_event("switch_room", %{"code" => code}, socket) do
    RoomEvents.switch_room(socket, code)
  end

  # Name events
  def handle_event("open_name_modal", _params, socket), do: SettingsEvents.open_name_modal(socket)

  def handle_event("close_name_modal", _params, socket),
    do: SettingsEvents.close_name_modal(socket)

  def handle_event("update_name_input", %{"name" => name}, socket) do
    SettingsEvents.update_name_input(socket, name)
  end

  def handle_event("save_name", %{"name" => name}, socket) do
    SettingsEvents.save_name(socket, name)
  end

  # Note events
  def handle_event("open_note_modal", _params, socket), do: NoteEvents.open_note_modal(socket)
  def handle_event("close_note_modal", _params, socket), do: NoteEvents.close_note_modal(socket)

  def handle_event("update_note", %{"content" => content}, socket) do
    NoteEvents.update_note(socket, content)
  end

  def handle_event("save_note", %{"content" => content}, socket) do
    NoteEvents.save_note(socket, content)
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
          Social.set_photo_thumbnail(
            photo_id_int,
            thumbnail,
            socket.assigns.user_id,
            socket.assigns.room.code
          )
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
  def handle_event("open_settings_modal", _params, socket),
    do: SettingsEvents.open_settings_modal(socket)

  def handle_event("close_settings_modal", _params, socket),
    do: SettingsEvents.close_settings_modal(socket)

  def handle_event("switch_settings_tab", %{"tab" => tab}, socket) do
    SettingsEvents.switch_settings_tab(socket, tab)
  end

  # Network modal events
  def handle_event("open_network_modal", _params, socket),
    do: NetworkEvents.open_network_modal(socket)

  def handle_event("close_network_modal", _params, socket),
    do: NetworkEvents.close_network_modal(socket)

  def handle_event("switch_network_tab", %{"tab" => tab}, socket) do
    NetworkEvents.switch_network_tab(socket, tab)
  end

  def handle_event("sign_out", _params, socket) do
    SettingsEvents.sign_out(socket)
  end

  def handle_event("view_full_image", %{"photo_id" => photo_id}, socket) do
    PhotoEvents.view_full_image(socket, photo_id)
  end

  def handle_event("close_image_modal", _params, socket) do
    PhotoEvents.close_image_modal(socket)
  end

  def handle_event("next_photo", _params, socket) do
    PhotoEvents.next_photo(socket)
  end

  def handle_event("prev_photo", _params, socket) do
    PhotoEvents.prev_photo(socket)
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

      socket.assigns.viewing_note ->
        {:noreply, assign(socket, :viewing_note, nil)}

      true ->
        {:noreply, socket}
    end
  end

  def handle_event("view_full_note", params, socket) do
    NoteEvents.view_full_note(socket, params)
  end

  def handle_event("close_view_note", _params, socket) do
    NoteEvents.close_view_note(socket)
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
    RoomEvents.create_invite(socket)
  end

  def handle_event("search_friends", %{"query" => query}, socket) do
    NetworkEvents.search_friends(socket, query)
  end

  def handle_event("add_trusted_friend", %{"user_id" => user_id_str}, socket) do
    NetworkEvents.add_trusted_friend(socket, user_id_str)
  end

  def handle_event("confirm_trust", %{"user_id" => user_id_str}, socket) do
    NetworkEvents.confirm_trust(socket, user_id_str)
  end

  # --- Room Member Management ---

  def handle_event("search_member_invite", %{"query" => query}, socket) do
    RoomEvents.search_member_invite(socket, query)
  end

  def handle_event("invite_to_room", %{"user_id" => user_id}, socket) do
    RoomEvents.invite_to_room(socket, user_id)
  end

  def handle_event("remove_room_member", %{"user_id" => user_id}, socket) do
    RoomEvents.remove_room_member(socket, user_id)
  end

  def handle_event("switch_feed", %{"mode" => mode}, socket) when mode in ["room", "friends"] do
    FeedEvents.switch_feed(socket, mode)
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

  def handle_event("open_invite_modal", _, socket) do
    {:noreply, assign(socket, :show_invite_modal, true)}
  end

  def handle_event("close_invite_modal", _, socket) do
    {:noreply, assign(socket, :show_invite_modal, false)}
  end

  def handle_event("set_feed_view", %{"view" => view}, socket) do
    FeedEvents.set_feed_view(socket, view)
  end

  # Toggle the chat panel visibility in split-view layout
  def handle_event("toggle_chat_panel", _, socket) do
    new_show = not socket.assigns.show_chat_panel

    socket =
      socket
      |> assign(:show_chat_panel, new_show)
      # Ensure we're in room mode
      |> assign(:feed_mode, "room")

    # Load chat messages and subscribe if opening chat
    socket =
      if new_show do
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
  def handle_event(
        "send_room_message",
        %{"encrypted_content" => encrypted, "nonce" => nonce},
        socket
      ) do
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
  def handle_event(
        "send_room_voice_note",
        %{"encrypted_content" => encrypted, "nonce" => nonce, "duration_ms" => duration},
        socket
      ) do
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
                nil ->
                  {[], true}

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

  def handle_event("vote_recovery", params, socket) do
    NetworkEvents.vote_recovery(socket, params)
  end

  # --- Progress Handler ---

  # Validate file content by checking magic bytes (file signature)

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

              {:ok,
               %{
                 data_url: "data:#{validated_type};base64,#{base64}",
                 content_type: validated_type,
                 file_size: file_size
               }}

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
           |> put_flash(
             :error,
             "Invalid file type. Please upload a valid image (JPEG, PNG, GIF, or WebP)."
           )}

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
               |> assign(
                 :photo_order,
                 merge_photo_order(socket.assigns.photo_order, [photo.id], :front)
               )
               |> stream_insert(:items, photo_with_type, at: 0)
               |> push_event("photo_uploaded", %{photo_id: photo.id})}

            {:error, _} ->
              {:noreply,
               socket |> assign(:uploading, false) |> put_flash(:error, "Upload failed")}
          end
      end
    end
  end

  def handle_progress(name, entry, socket) do
    PhotoEvents.handle_progress(name, entry, socket)
  end

  # --- PubSub Handlers ---

  # Handle real-time room creation (e.g., when a friendship creates a DM room)
  def handle_info({:room_created, room}, socket) do
    PubSubHandlers.handle_room_created(socket, room)
  end

  # Handle real-time public room creation (for all users to see new public rooms)
  def handle_info({:public_room_created, room}, socket) do
    PubSubHandlers.handle_public_room_created(socket, room)
  end

  def handle_info({:new_photo, photo}, socket) do
    PubSubHandlers.handle_new_photo(socket, photo)
  end

  def handle_info({:new_note, note}, socket) do
    PubSubHandlers.handle_new_note(socket, note)
  end

  def handle_info({:photo_deleted, %{id: id}}, socket) do
    PubSubHandlers.handle_photo_deleted(socket, id)
  end

  def handle_info(
        {:photo_thumbnail_updated, %{id: photo_id, thumbnail_data: thumbnail_data}},
        socket
      ) do
    PubSubHandlers.handle_photo_thumbnail_updated(socket, photo_id, thumbnail_data)
  end

  # Handle new room message from PubSub
  def handle_info({:new_room_message, message}, socket) do
    PubSubHandlers.handle_new_room_message(socket, message)
  end

  def handle_info({:note_deleted, %{id: id}}, socket) do
    PubSubHandlers.handle_note_deleted(socket, id)
  end

  def handle_info(%{event: "presence_diff", payload: diff}, socket) do
    PubSubHandlers.handle_presence_diff(socket, diff)
  end

  # Ignore task failure messages we don't explicitly handle
  def handle_info({_ref, :error}, socket), do: {:noreply, socket}
  # Ignore task DOWN messages (e.g., async thumbnail generation)
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket), do: {:noreply, socket}

  # --- Helpers ---

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

  defp maybe_bootstrap_identity(%{assigns: %{user_id: user_id}} = socket, _params)
       when not is_nil(user_id),
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

  # Handle public feed broadcasts
  def handle_info({:new_public_photo, photo}, socket) do
    PubSubHandlers.handle_new_public_photo(socket, photo)
  end

  def handle_info({:new_public_note, note}, socket) do
    PubSubHandlers.handle_new_public_note(socket, note)
  end
end
