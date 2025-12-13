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
  alias FriendsWeb.HomeLive.Events.SessionEvents
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

    socket = SessionEvents.maybe_bootstrap_identity(socket, get_connect_params(socket))

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

      socket = SessionEvents.maybe_bootstrap_identity(socket, get_connect_params(socket))

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

  # --- Events ---

  def handle_event(
        "set_user_id",
        %{"browser_id" => browser_id, "fingerprint" => fingerprint},
        socket
      ) do
    SessionEvents.set_user_id(socket, browser_id, fingerprint)
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
    PhotoEvents.regenerate_thumbnails(socket)
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
    FeedEvents.load_more(socket)
  end

  def handle_event("vote_recovery", params, socket) do
    NetworkEvents.vote_recovery(socket, params)
  end

  # --- Progress Handler ---

  # Validate file content by checking magic bytes (file signature)

  # Generate thumbnail for photos that don't have one
  # Generate thumbnail from base64 image data


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

  # Handle public feed broadcasts
  def handle_info({:new_public_photo, photo}, socket) do
    PubSubHandlers.handle_new_public_photo(socket, photo)
  end

  def handle_info({:new_public_note, note}, socket) do
    PubSubHandlers.handle_new_public_note(socket, note)
  end

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


end
