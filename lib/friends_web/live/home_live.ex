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
  alias FriendsWeb.HomeLive.Lifecycle

  import Ecto.Query
  require Logger

  def mount(params, session, socket) do
    Lifecycle.mount(params, session, socket)
  end

  def handle_params(params, uri, socket) do
    Lifecycle.handle_params(params, uri, socket)
  end

  # --- Events ---

  def handle_event("toggle_user_dropdown", _params, socket) do
    {:noreply, assign(socket, :show_user_dropdown, !socket.assigns.show_user_dropdown)}
  end

  def handle_event("close_user_dropdown", _params, socket) do
    {:noreply, assign(socket, :show_user_dropdown, false)}
  end

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
  def handle_event("open_feed_note_modal", _params, socket), do: NoteEvents.open_feed_note_modal(socket)
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



end
