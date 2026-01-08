defmodule FriendsWeb.HomeLive.Lifecycle do
  @moduledoc """
  Handles initialization (mount) and navigation (handle_params) logic for HomeLive.
  """
  import Phoenix.Component
  import Phoenix.LiveView
  # For ~p sigil
  use Phoenix.VerifiedRoutes, endpoint: FriendsWeb.Endpoint, router: FriendsWeb.Router, statics: ~w(assets fonts images favicon.ico robots.txt)
  
  import FriendsWeb.HomeLive.Helpers
  alias Friends.Social
  alias Friends.Social.Presence
  alias FriendsWeb.HomeLive.GraphHelper
  
  # Event modules needed for initial setup/subscriptions
  alias FriendsWeb.HomeLive.Events.SessionEvents
  alias FriendsWeb.HomeLive.Events.PhotoEvents
  require Logger

  @initial_batch 20

  def mount(%{"room" => room_code}, session, socket) do
    mount_room(socket, room_code, session)
  end

  def mount(_params, session, socket) do
    # Dashboard / Index
    mount_dashboard(socket, session)
  end

  # --- Mount Implementations ---

  defp mount_dashboard(socket, session) do
    session_id = generate_session_id()

    # Try to get user from session
    {session_user, session_user_id, session_user_color, session_user_name} =
      load_session_user(session)

    # Redirect guests to auth page
    if is_nil(session_user) do
      {:ok, push_navigate(socket, to: ~p"/auth")}
    else
      if connected?(socket) do
        # Subscribe to user's personal channel
        Phoenix.PubSub.subscribe(Friends.PubSub, "friends:user:#{session_user.id}")
        # Subscribe to public feed updates
        Social.subscribe_to_public_feed(session_user.id)
        # Subscribe to global presence for live friend status
        Presence.subscribe_global()
        # Track this user as online globally
        Presence.track_global(self(), session_user.id, session_user_color, session_user_name)
        # Subscribe to global events for live welcome graph updates (new users, connections)
        Phoenix.PubSub.subscribe(Friends.PubSub, "friends:global")
      end

      # Load initial public feed items and contacts
      # Admin sees ALL content, regular users see contacts only
      is_admin = Social.is_admin?(session_user)
      feed_items = if is_admin do
        Social.list_admin_feed_items(20)
      else
        Social.list_public_feed_items(session_user.id, 20)
      end
      # Sort friends by activity (most contacted first)
      friends = Social.list_friends_by_activity(session_user.id)
      trusted_friends = Social.list_trusted_friends(session_user.id)
      incoming_trust_requests = Social.list_pending_trust_requests(session_user.id)
      pending_requests = Social.list_friend_requests(session_user.id)
      outgoing_friend_requests = Social.list_sent_friend_requests(session_user.id)
      devices = Social.list_user_devices(session_user.id)
      
      # Fetch navigation lists - admin sees ALL groups, regular users see their own
      user_private_rooms = if is_admin do
        Social.list_all_groups(100)
      else
        Social.list_user_groups(session_user.id)
      end
      direct_rooms = Social.list_user_dms(session_user.id)

      # Get online friend IDs for presence indicators
      friend_user_ids = Enum.map(friends, & &1.user.id)
      online_friend_ids = if connected?(socket), do: Presence.filter_online(friend_user_ids), else: []

      socket =
        socket
        |> assign(:session_id, session_id)
        |> assign(:room, nil)
        |> assign_persistent_notification(session_user.id)
        |> assign(:page_title, "New Internet")
        |> assign(:current_user, session_user)
        |> assign(:user_id, session_user_id)
        |> assign(:user_color, session_user_color)
        |> assign(:user_name, session_user_name)
        |> assign(:auth_status, :authed)
        |> assign(:viewers, [])
        |> assign(:show_chat_panel, false)
        |> assign(:show_room_modal, false)
        |> assign(:show_name_modal, false)
        |> assign(:show_note_modal, false)
        |> assign(:note_modal_action, nil)
        |> assign(:show_settings_modal, false)
        |> assign(:show_network_modal, false)
        # Dashboard specific assigns
        |> assign(:user_rooms, Social.list_user_rooms(session_user.id))
        |> assign(:dashboard_tab, "contacts")
        |> assign(:create_group_modal, false)
        |> assign(:new_room_name, "")
        |> assign(:join_code, "")
        |> assign(:current_route, "/")
        |> assign(:show_header_dropdown, false)
        |> assign(:room_access_denied, false)
        |> assign(:feed_mode, "dashboard")
        |> assign(:toolbar_context, :feed)
        |> assign(:show_nav_menu, false)
        |> assign(:show_create_menu, false)
        # Public feed assigns
        |> assign(:friends, friends)
        |> assign(:trusted_friends, trusted_friends)
        |> assign(:trusted_friend_ids, Enum.map(trusted_friends, & &1.trusted_user.id))
        |> assign(:incoming_trust_requests, incoming_trust_requests)
        |> assign(:pending_requests, pending_requests)
        |> assign(:outgoing_friend_requests, outgoing_friend_requests)
        |> assign(:user_private_rooms, user_private_rooms)
        |> assign(:direct_rooms, direct_rooms)
        |> assign(:total_unread_count, Social.get_total_unread_count(session_user.id))
        |> assign(:devices, devices)
        |> assign(:show_devices_modal, false)
        |> assign(:show_pairing_modal, false)
        |> assign(:pairing_token, nil)
        |> assign(:pairing_url, nil)
        |> assign(:pairing_expires_at, nil)
        # Graph data is lazy-loaded when graph drawer opens (performance optimization)
        |> assign(:graph_data, nil)
        # Welcome graph data for empty feed state - ensure current user is included
        |> assign(:welcome_graph_data, 
          GraphHelper.ensure_user_in_welcome_graph(
            session_user, 
            Friends.GraphCache.get_welcome_graph_data()
          )
        )
        # New user = no friends yet (for showing opt-out checkbox)
        |> assign(:is_new_user, length(friends) == 0)
        |> assign(:show_nav_drawer, false)
        |> assign(:show_graph_drawer, false)
        |> assign(:show_sign_out_modal, false)
        |> assign(:show_chord_modal, false)
        |> assign(:chord_data, nil)
        |> assign(:contacts_collapsed, false)
        |> assign(:groups_collapsed, false)
        |> assign(:fab_expanded, false)
        |> assign(:show_mobile_chat, false)
        |> assign(:note_input, "")
        |> assign(:recording_voice, false)
        |> assign(:show_image_modal, false)
        |> assign(:full_image_data, nil)
        |> assign(:feed_item_count, length(feed_items))
        |> assign(:no_more_items, length(feed_items) < 20)
        |> assign(:show_nav_panel, false)
        |> assign(:show_breadcrumbs, false)
        |> assign(:show_groups_sheet, false)
        |> assign(:group_search_query, "")
        |> assign(:group_search_results, [])
        |> assign(:show_contact_sheet, false)
        |> assign(:show_profile_sheet, false)
        |> assign(:show_avatar_menu, false)
        |> assign(:contact_mode, :list_contacts)
        |> assign(:contact_sheet_search, "")
        |> assign(:contact_search_results, [])
        |> assign(:show_people_modal, false)
        |> assign(:show_groups_modal, false)
        |> assign(:room_members, [])
        # Typing users (for rooms, init empty for dashboard)
        |> assign(:typing_users, %{})
        # Live presence - friend IDs currently online
        |> assign(:online_friend_ids, MapSet.new(online_friend_ids))
        |> assign(:photo_order, photo_ids(feed_items))
        |> stream(:feed_items, feed_items, dom_id: &"feed-item-#{&1.type}-#{&1.id}")

      # Allow uploads for the public feed
      socket =
        allow_upload(socket, :feed_photo,
          accept: ~w(.jpg .jpeg .png .gif .webp),
          max_entries: 10,
          max_file_size: 20_000_000,
          auto_upload: true,
          progress: &FriendsWeb.HomeLive.Events.PhotoEvents.handle_progress/3
        )

      # Allow avatar uploads
      socket =
        allow_upload(socket, :avatar,
          accept: ~w(.jpg .jpeg .png .gif .webp),
          max_entries: 1,
          max_file_size: 5_000_000,
          auto_upload: true,
          progress: &FriendsWeb.HomeLive.handle_avatar_progress/3
        )

      socket = SessionEvents.maybe_bootstrap_identity(socket, get_connect_params(socket))

      # No real-time updates for welcome graph for now to keep it minimal


      {:ok, socket}
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
      {_photos, _notes, items, friends} =
        if can_access do
          photos = Social.list_photos(room.id, @initial_batch, offset: 0)
          notes = Social.list_notes(room.id, @initial_batch, offset: 0)
          # Fetch friends for invite modal
          friends_list = if session_user, do: Social.list_friends(session_user.id), else: []
          {photos, notes, build_items(photos, notes), friends_list}
        else
          {[], [], [], []}
        end

      # Subscribe when connected
      if connected?(socket) and can_access do
        Logger.info("Subscribing to private room: friends:room:#{room.code} (is_private: #{room.is_private})")
        Social.subscribe(room.code)
        Phoenix.PubSub.subscribe(Friends.PubSub, "friends:presence:#{room.code}")

        if room.is_private do
          Social.subscribe_to_room_chat(room.id)
          # Subscribe to live typing events
          Phoenix.PubSub.subscribe(Friends.PubSub, "room:#{room.id}:typing")
          # Subscribe to warmth pulse events (ambient awareness)
          Phoenix.PubSub.subscribe(Friends.PubSub, "room:#{room.id}:warmth")
          # Subscribe to viewing events (shared attention)
          Phoenix.PubSub.subscribe(Friends.PubSub, "room:#{room.id}:viewing")
          # Subscribe to walkie-talkie events (live audio)
          Phoenix.PubSub.subscribe(Friends.PubSub, "room:#{room.id}:walkie")
        end

        # Subscribe to user-specific events (room creations, etc.)
        if session_user do
          Phoenix.PubSub.subscribe(Friends.PubSub, "friends:user:#{session_user.id}")
        end

        # Request identity from client once socket is connected
        push_event(socket, "request_identity", %{})

        # Regenerate any missing thumbnails in the background so placeholders get filled
        # Note: PhotoEvents must be aliased or full module name used
        Task.start(fn -> PhotoEvents.regenerate_all_missing_thumbnails(room.id, room.code) end)
      end

      # Subscribe to global presence for friend status
      if connected?(socket) and session_user do
        Presence.subscribe_global()
        Presence.track_global(self(), session_user.id, session_user_color, session_user_name)
      end

      # Get online friend IDs
      online_friend_ids = 
        if connected?(socket) and length(friends) > 0 do
          friend_user_ids = Enum.map(friends, & &1.user.id)
          Presence.filter_online(friend_user_ids)
        else
          []
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
        |> assign(:toolbar_context, :room)
        # "content" or "chat"
        |> assign(:room_tab, "content")
        |> assign(
          :room_messages,
          if(room.is_private and can_access, do: Social.list_room_messages(room.id, 200), else: [])
        )
        |> assign(:new_chat_message, "")
        |> assign(:recording_voice, false)
        # Collapsible chat panel, default open for private
        |> assign(:show_chat_panel, room.is_private)
        |> assign(:show_mobile_chat, false)
        # Fluid room state
        |> assign(:show_members_panel, false)
        |> assign(:chat_expanded, false)
        # Chat visibility toggle (show by default if room is private and has access)
        |> assign(:show_chat, room.is_private and can_access)
        # Add menu toggle (unified + button)
        |> assign(:show_add_menu, false)
        # Live typing - track what other users are typing
        |> assign(:typing_users, %{})
        # Warmth pulses - track content currently being viewed by others
        |> assign(:warmth_pulses, %{})
        # Photo viewers - track who's viewing which photos (shared attention)
        |> assign(:photo_viewers, %{})
        # FAB and collapsible UI state
        |> assign(:fab_expanded, false)
        |> assign(:contacts_collapsed, false)
        |> assign(:groups_collapsed, false)
        |> assign(:show_room_modal, false)
        |> assign(:show_nav_drawer, false)
        |> assign(:show_graph_drawer, false)
        |> assign(:show_chord_modal, false)
        |> assign(:chord_data, nil)
        |> assign(:graph_data, GraphHelper.build_graph_data(session_user))
        |> assign(:show_name_modal, false)
        |> assign(:show_note_modal, false)
        |> assign(:show_sign_out_modal, false)
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
        |> assign(:invites, [])
        |> assign(:trusted_friends, [])
        |> assign(:outgoing_trust_requests, [])
        |> assign(:show_contact_sheet, false)
        |> assign(:show_profile_sheet, false)
        |> assign(:show_avatar_menu, false)
        |> assign(:contact_mode, :list_contacts)
        |> assign(:contact_sheet_search, "")
        |> assign(:contact_search_results, [])
        |> assign(:show_people_modal, false)
        |> assign(:show_groups_modal, false)
        |> assign(:trusted_friend_ids, [])
        |> assign(:incoming_trust_requests, [])
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
          if(session_user, do: Social.list_user_groups(session_user.id), else: [])
        )
        |> assign(
          :direct_rooms,
          if(session_user, do: Social.list_user_dms(session_user.id), else: [])
        )
        |> assign(
          :user_rooms,
          if(session_user, do: Social.list_user_rooms(session_user.id), else: [])
        )
        |> assign(:public_rooms, Social.list_public_rooms())
        |> assign(:show_header_dropdown, false)
        |> assign(:show_invite_modal, false)
        |> assign(:current_route, "/r/#{room.code}")
        |> assign(:network_filter, "trusted")
        |> assign(:room_access_denied, not can_access)
        |> assign(:show_image_modal, false)
        |> assign(:show_breadcrumbs, false)
        |> assign(:full_image_data, nil)
        |> assign(:photo_order, if(can_access, do: photo_ids(items), else: []))
        |> assign(:show_nav_menu, false)
        |> assign(:show_create_menu, false)
        |> assign(:current_photo_id, nil)
        |> assign(:friends, friends)
        # Group/members sheet state
        |> assign(:show_group_sheet, false)
        |> assign(:group_search, "")
        |> assign(:show_pairing_modal, false)
        |> assign(:pairing_token, nil)
        |> assign(:pairing_url, nil)
        |> assign(:pairing_expires_at, nil)
        |> assign(:online_friend_ids, MapSet.new(online_friend_ids))
        |> assign_persistent_notification(session_user.id)
        |> stream(:items, items, dom_id: &"item-#{&1.unique_id}")
        |> maybe_allow_upload(can_access)

      socket = SessionEvents.maybe_bootstrap_identity(socket, get_connect_params(socket))

      {:ok, socket}
    end
  end

  # --- Handle Params ---

  def handle_params(%{"room" => room_code} = params, _uri, socket) do
    current_room_code = socket.assigns[:room] && socket.assigns.room.code
    
    # Check for actions
    show_invite = params["action"] == "invite"
    expand_chat = params["action"] == "chat"

    if current_room_code != room_code do
      old_room = socket.assigns[:room]

      # Only cleanup subscriptions if coming from another room
      if old_room do
        if socket.assigns.user_id do
          Presence.untrack_user(self(), old_room.code, socket.assigns.user_id)
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
        
        # Mark room as read
        if socket.assigns.current_user do
           Social.mark_room_read(room.id, socket.assigns.current_user.id)
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
       |> assign(:show_chat_panel, room.is_private or expand_chat)
       |> assign(:chat_expanded, expand_chat)
       |> assign(
         :room_messages,
         if(room.is_private and can_access, do: Social.list_room_messages(room.id, 200), else: [])
       )
       |> assign(:photo_order, if(can_access, do: photo_ids(items), else: []))
       |> assign(:user_rooms, private_rooms)
       |> assign(:user_private_rooms, private_rooms)
       |> assign(:public_rooms, public_rooms)
       |> assign(:feed_mode, "room")
       |> assign(:recording_voice, false)
       |> assign(:current_route, "/r/#{room.code}")
       |> assign(
         :room_members,
         if(room.is_private and can_access, do: Social.list_room_members(room.id), else: [])
       )
       |> assign(:show_invite_modal, show_invite)
       |> stream(:items, items, reset: true, dom_id: &"item-#{&1.unique_id}")
       # Clear persistent notification if we just entered that room
       |> assign(:persistent_notification, 
          if(socket.assigns[:persistent_notification] && socket.assigns.persistent_notification.room_code == room_code, 
             do: nil, 
             else: socket.assigns[:persistent_notification])
       )}
    else
      # Update params even if room didn't change
      show_invite = params["action"] == "invite"
      expand_chat = params["action"] == "chat"
      
      socket = 
        if expand_chat && socket.assigns.current_user && socket.assigns[:room] do
           Social.mark_room_read(socket.assigns.room.id, socket.assigns.current_user.id)
           
           # Clear notification if matches
           if socket.assigns[:persistent_notification] && 
              socket.assigns.persistent_notification.room_code == socket.assigns.room.code do
             assign(socket, :persistent_notification, nil)
           else
             socket
           end
        else
           socket
        end
      
      {:noreply, 
       socket 
       |> assign(:show_invite_modal, show_invite)
       |> assign(:chat_expanded, expand_chat)
       |> assign(:show_chat_panel, if(expand_chat, do: true, else: socket.assigns.show_chat_panel))}
    end
  end

  def handle_params(params, _uri, socket) when socket.assigns.live_action == :index do
    # When navigating to dashboard, ensure we clean up room subscriptions if coming from a room
    if socket.assigns[:room] do
      old_room = socket.assigns.room
      Social.unsubscribe(old_room.code)
      Phoenix.PubSub.unsubscribe(Friends.PubSub, "friends:presence:#{old_room.code}")

      if socket.assigns.user_id do
        Presence.untrack_user(self(), old_room.code, socket.assigns.user_id)
      end
    end

    # Refresh user rooms
    user_rooms =
      if socket.assigns.current_user do
        Social.list_user_dashboard_rooms(socket.assigns.current_user.id)
      else
        []
      end
      
    # Check if we should open the contacts sheet
    show_contacts = params["action"] == "contacts"

    {:noreply,
     socket
     |> assign(:room, nil)
     |> assign(:page_title, "New Internet")
     |> assign(:user_rooms, user_rooms)
     |> assign(:feed_mode, "dashboard")
     |> assign(:current_route, "/")
     |> assign(:show_contact_sheet, show_contacts)}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  # --- Privates ---

  defp load_session_user(session) do
    case session["user_id"] do
      nil ->
        {nil, nil, nil, nil}

      user_id ->
        case Social.get_user(user_id) do
          nil ->
            {nil, nil, nil, nil}

          user ->
            # Using Helpers.colors() implicitly or via module attribute if imported?
            # Helpers module has helper 'colors()' or we can use the list.
            # But the original code used @colors.
            # Let's check Helpers.
            colors = FriendsWeb.HomeLive.Helpers.colors()
            color = Enum.at(colors, rem(user.id, length(colors)))
            {user, "user-#{user.id}", color, user.display_name || user.username}
        end
    end
  end
  
  defp maybe_allow_upload(socket, true) do
    socket
    |> allow_upload(:photo,
      accept: ~w(.jpg .jpeg .png .gif .webp),
      max_entries: 10,
      max_file_size: 20_000_000,
      auto_upload: true,
      progress: &FriendsWeb.HomeLive.Events.PhotoEvents.handle_progress/3
    )
    |> allow_upload(:avatar,
      accept: ~w(.jpg .jpeg .png .gif .webp),
      max_entries: 1,
      max_file_size: 5_000_000,
      auto_upload: true
    )
  end

  defp maybe_allow_upload(socket, false), do: socket

  # Small helper to get user id from socket assigns if loaded
  defp current_user_id(socket) do
    case socket.assigns.current_user do
      nil -> nil
      user -> user.id
    end
  end

  defp assign_persistent_notification(socket, user_id) do
    notification = 
      case Social.get_latest_unread_message(user_id) do
        nil -> nil
        message ->
          # Determine room code and room ID for navigation/dismissal
          {room_code, room_id, room_name} =
            cond do
              Ecto.assoc_loaded?(message.conversation) && message.conversation && message.conversation.type == "direct" ->
                # It's a DM, find the room based on sender (partner)
                case Social.get_or_create_dm_room(user_id, message.sender_id) do
                  {:ok, room} -> {room.code, room.id, room.name}
                  _ -> {nil, nil, nil}
                end
                
              # Fallback specifically for room-based messages
              message.room_id -> 
                 case Social.get_room(message.room_id) do
                   nil -> {nil, nil, nil}
                   room -> {room.code, room.id, room.name}
                 end

              true -> {nil, nil, nil}
            end

          if room_code do
             display_text = case message.content_type do
               "text" -> "Sent a message"
               "voice" -> "Sent a voice message"
               "image" -> "Sent a photo"
               _ -> "Sent one new message"
             end

             %{
              id: "msg-#{message.id}",
              sender_username: "@#{message.sender.username}",
              room_id: room_id, # CRITICAL for persistent dismissal
              conversation_id: message.conversation_id,
              room_code: room_code,
              room_name: room_name || "Chat",
              text: display_text,
              timestamp: message.inserted_at,
              count: 1
            }
          else
            nil
          end
      end

    assign(socket, :persistent_notification, notification)
  end
end
