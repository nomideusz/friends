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
      end

      # Load initial public feed items and contacts
      feed_items = Social.list_public_feed_items(session_user.id, 20)
      friends = Social.list_friends(session_user.id)

      socket =
        socket
        |> assign(:session_id, session_id)
        |> assign(:room, nil)
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
        # Required for layout to not crash
        |> assign(:room_access_denied, false)
        |> assign(:feed_mode, "dashboard")
        # Public feed assigns
        |> assign(:friends, friends)
        |> assign(:graph_data, GraphHelper.build_graph_data(session_user))
        # Constellation for users with < 3 friends (opt-out checked client-side via localStorage)
        |> assign(:show_constellation, length(friends) < 3)
        |> assign(:constellation_data, if(length(friends) < 3, do: GraphHelper.build_constellation_data(session_user), else: nil))
        |> assign(:show_nav_drawer, false)
        |> assign(:show_graph_drawer, false)
        |> assign(:contacts_collapsed, false)
        |> assign(:groups_collapsed, false)
        |> assign(:fab_expanded, false)
        |> assign(:show_mobile_chat, false)
        |> assign(:note_input, "")
        |> assign(:recording_voice, false)
        |> assign(:uploading, false)
        |> assign(:show_image_modal, false)
        |> assign(:full_image_data, nil)
        |> assign(:feed_item_count, length(feed_items))
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

      socket = SessionEvents.maybe_bootstrap_identity(socket, get_connect_params(socket))

      # Subscribe to new user signups if showing constellation
      if connected?(socket) and socket.assigns[:show_constellation] do
        Phoenix.PubSub.subscribe(Friends.PubSub, "friends:new_users")
      end

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
        # FAB and collapsible UI state
        |> assign(:fab_expanded, false)
        |> assign(:contacts_collapsed, false)
        |> assign(:groups_collapsed, false)
        |> assign(:show_room_modal, false)
        |> assign(:show_nav_drawer, false)
        |> assign(:show_graph_drawer, false)
        |> assign(:graph_data, GraphHelper.build_graph_data(session_user))
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
        |> assign(:full_image_data, nil)
        |> assign(:photo_order, if(can_access, do: photo_ids(items), else: []))
        |> assign(:current_photo_id, nil)
        |> assign(:friends, friends)
        |> stream(:items, items, dom_id: &"item-#{&1.unique_id}")
        |> maybe_allow_upload(can_access)

      socket = SessionEvents.maybe_bootstrap_identity(socket, get_connect_params(socket))

      {:ok, socket}
    end
  end

  # --- Handle Params ---

  def handle_params(%{"room" => room_code} = params, _uri, socket) do
    current_room_code = socket.assigns[:room] && socket.assigns.room.code
    
    # Check for actions (e.g. auto open invite modal)
    show_invite = params["action"] == "invite"

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
       |> assign(:user_rooms, private_rooms)
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
       |> assign(:show_invite_modal, show_invite)
       |> stream(:items, items, reset: true, dom_id: &"item-#{&1.unique_id}")}
    else
      # Update invite modal even if room didn't change (e.g. navigating to same room with ?action=invite)
      show_invite = params["action"] == "invite"
      {:noreply, assign(socket, :show_invite_modal, show_invite)}
    end
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
     |> assign(:page_title, "New Internet")
     |> assign(:user_rooms, user_rooms)
     |> assign(:feed_mode, "dashboard")
     |> assign(:current_route, "/")}
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
    allow_upload(socket, :photo,
      accept: ~w(.jpg .jpeg .png .gif .webp),
      max_entries: 10,
      max_file_size: 20_000_000,
      auto_upload: true,
      progress: &FriendsWeb.HomeLive.Events.PhotoEvents.handle_progress/3
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
end
