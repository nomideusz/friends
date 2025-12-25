defmodule FriendsWeb.HomeLive do
  use FriendsWeb, :live_view

  alias Friends.Social

  import FriendsWeb.HomeLive.Helpers
  import FriendsWeb.HomeLive.Components.SettingsComponents
  import FriendsWeb.HomeLive.Components.DrawerComponents
  import FriendsWeb.HomeLive.Components.FluidRoomComponents
  import FriendsWeb.HomeLive.Components.FluidFeedComponents
  import FriendsWeb.HomeLive.Components.FluidModalComponents
  import FriendsWeb.HomeLive.Components.FluidContactComponents
  import FriendsWeb.HomeLive.Components.FluidGroupComponents
  import FriendsWeb.HomeLive.Components.FluidProfileComponents
  import FriendsWeb.HomeLive.Components.FluidBottomToolbar
  import FriendsWeb.HomeLive.Components.FluidCreateMenu
  import FriendsWeb.HomeLive.Components.FluidOmnibox
  import FriendsWeb.HomeLive.Components.FluidUploadIndicator
  alias FriendsWeb.HomeLive.Events.FeedEvents
  alias FriendsWeb.HomeLive.Events.PhotoEvents
  alias FriendsWeb.HomeLive.Events.RoomEvents
  alias FriendsWeb.HomeLive.Events.NoteEvents
  alias FriendsWeb.HomeLive.Events.NetworkEvents
  alias FriendsWeb.HomeLive.Events.SettingsEvents
  alias FriendsWeb.HomeLive.Events.SessionEvents
  alias FriendsWeb.HomeLive.Events.ChatEvents
  alias FriendsWeb.HomeLive.PubSubHandlers
  alias FriendsWeb.HomeLive.Lifecycle

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

  def handle_event("toggle_contacts", _params, socket) do
    {:noreply, assign(socket, :contacts_collapsed, !socket.assigns[:contacts_collapsed])}
  end

  def handle_event("open_contacts_sheet", _, socket) do
    NetworkEvents.open_contacts_sheet(socket)
  end

  def handle_event("toggle_groups", _params, socket) do
    {:noreply, assign(socket, :groups_collapsed, !socket.assigns[:groups_collapsed])}
  end

  # No-op handler for forms where JS handles submit but phx-submit needs a value
  def handle_event("noop", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("toggle_nav_drawer", _params, socket) do
    {:noreply, assign(socket, :show_nav_drawer, !socket.assigns[:show_nav_drawer])}
  end

  def handle_event("toggle_graph_drawer", _params, socket) do
    {:noreply, assign(socket, :show_graph_drawer, !socket.assigns[:show_graph_drawer])}
  end

  def handle_event("show_welcome_graph", _params, socket) do
    {:noreply, assign(socket, :show_welcome_graph, true)}
  end

  def handle_event("show_my_constellation", _params, socket) do
    {:noreply, assign(socket, :show_graph_drawer, true)}
  end

  def handle_event("toggle_fab", _params, socket) do
    {:noreply, assign(socket, :fab_expanded, !socket.assigns[:fab_expanded])}
  end

  def handle_event("toggle_chat_visibility", _params, socket) do
    ChatEvents.toggle_chat_visibility(socket)
  end

  def handle_event("toggle_add_menu", _params, socket) do
    {:noreply, assign(socket, :show_add_menu, !socket.assigns[:show_add_menu])}
  end

  def handle_event("open_profile_sheet", _params, socket) do
    {:noreply, assign(socket, :show_profile_sheet, true)}
  end

  def handle_event("close_profile_sheet", _params, socket) do
    {:noreply, assign(socket, :show_profile_sheet, false)}
  end

  # --- Home Orb Events ---

  def handle_event("go_home", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_breadcrumbs, false)
     |> push_navigate(to: ~p"/")}
  end

  def handle_event("show_breadcrumbs", _params, socket) do
    # Toggle breadcrumbs visibility (auto-hide after 3s could be nice too, but toggle involves less state complexity for now)
    # Actually, let's make it show if hidden, hide if shown.
    # Ideally should hide on release, but my hook design implies "show on hold".
    # For now, let's just toggle.
    {:noreply, assign(socket, :show_breadcrumbs, !socket.assigns[:show_breadcrumbs])}
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

  # Avatar upload handlers
  def handle_avatar_progress(:avatar, entry, socket) do
    if entry.done? do
      uploaded_files =
        consume_uploaded_entries(socket, :avatar, fn %{path: path}, entry ->
          # Read file
          {:ok, binary} = File.read(path)

          # Upload to S3
          filename = "avatars/#{socket.assigns.current_user.id}-#{System.system_time(:second)}#{Path.extname(entry.client_name)}"
          case Friends.Storage.upload_file(binary, filename, entry.client_type) do
            {:ok, url} ->
              # Update user avatar
              case Social.update_user_avatar(socket.assigns.current_user.id, url) do
                {:ok, updated_user} ->
                  {:ok, updated_user}
                {:error, _} ->
                  {:ok, nil}
              end
            {:error, _} ->
              {:ok, nil}
          end
        end)

      case uploaded_files do
        [updated_user | _] when not is_nil(updated_user) ->
          {:noreply, assign(socket, :current_user, updated_user)}
        _ ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("validate_avatar", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("upload_avatar", _params, socket) do
    # Manual submission fallback, though auto_upload handles it
    {:noreply, socket}
  end

  def handle_event("delete_photo", %{"id" => id}, socket) do
    PhotoEvents.delete_photo(socket, id)
  end

  def handle_event("delete_note", %{"id" => id}, socket) do
    NoteEvents.delete_note(socket, id)
  end

  # Admin bulk deletion handlers
  def handle_event("delete_gallery", %{"batch_id" => batch_id}, socket) do
    PhotoEvents.delete_gallery(socket, batch_id)
  end

  def handle_event("admin_delete_room", %{"room_id" => room_id}, socket) do
    current_user = socket.assigns.current_user
    if Social.is_admin?(current_user) do
      case Social.admin_delete_room(room_id) do
        {:ok, _} ->
          # Refresh rooms list
          user_private_rooms = Social.list_all_groups(100)
          {:noreply,
           socket
           |> assign(:user_private_rooms, user_private_rooms)
           |> put_flash(:info, "Room deleted")}
        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Delete failed")}
      end
    else
      {:noreply, put_flash(socket, :error, "Admin only")}
    end
  end

  def handle_event("admin_delete_user", %{"user_id" => user_id}, socket) do
    current_user = socket.assigns.current_user
    if Social.is_admin?(current_user) do
      case Social.admin_delete_user(user_id) do
        {:ok, _} ->
          {:noreply, put_flash(socket, :info, "User deleted")}
        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Delete failed")}
      end
    else
      {:noreply, put_flash(socket, :error, "Admin only")}
    end
  end

  # Chat toggle events
  def handle_event("toggle_chat_expanded", _params, socket) do
    ChatEvents.toggle_chat_expanded(socket)
  end

  def handle_event("toggle_chat_visibility", _params, socket) do
    ChatEvents.toggle_chat_visibility(socket)
  end

  # Add menu toggle events (for unified + button)
  def handle_event("toggle_add_menu", _params, socket) do
    {:noreply, assign(socket, :show_add_menu, !socket.assigns[:show_add_menu])}
  end

  def handle_event("close_add_menu", _params, socket) do
    {:noreply, assign(socket, :show_add_menu, false)}
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

  def handle_event("save_feed_photo", _, socket) do
    PhotoEvents.save_feed_photo(socket)
  end

  # open_feed_note_modal and close_note_modal delegated to NoteEvents module (lines 203-205)

  def handle_event("view_feed_photo", %{"photo_id" => photo_id}, socket) do
    PhotoEvents.view_feed_photo(socket, photo_id)
  end

  def handle_event("view_gallery", %{"batch_id" => batch_id}, socket) do
    PhotoEvents.view_gallery(socket, batch_id)
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

  def handle_event("cancel_voice_recording", _, socket) do
    NoteEvents.cancel_voice_recording(socket)
  end

  def handle_event("post_public_voice", %{"audio_data" => _} = params, socket) do
    NoteEvents.post_public_voice(socket, params)
  end

  def handle_event("save_grid_voice_note", params, socket) do
    NoteEvents.save_grid_voice_note(socket, params)
  end

  def handle_event("stop_room_recording", _, socket) do
    {:noreply,
     socket
     |> assign(:recording_voice, false)
     |> push_event("stop_room_voice_recording", %{})}
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
  def handle_event("open_room_note_modal", _params, socket), do: NoteEvents.open_note_modal(socket)
  def handle_event("close_note_modal", _params, socket), do: NoteEvents.close_note_modal(socket)

  # Pin/unpin events (admin-only, handled in RoomEvents)
  def handle_event("pin_item", %{"type" => type, "id" => id}, socket) do
    RoomEvents.pin_item(socket, type, id)
  end

  def handle_event("unpin_item", %{"type" => type, "id" => id}, socket) do
    RoomEvents.unpin_item(socket, type, id)
  end
  
  def handle_event("view_feed_note", %{"note_id" => note_id}, socket) do
    NoteEvents.view_feed_note(socket, note_id)
  end

  def handle_event("view_full_note", %{"id" => _id, "content" => content, "user" => user, "time" => time}, socket) do
    # For room notes, we already have the data in params, just display it
    note_data = %{
      content: content,
      user: %{username: user},
      inserted_at: time
    }
    {:noreply, assign(socket, :viewing_note, note_data)}
  end

  def handle_event("update_note", %{"note" => content}, socket) do
    NoteEvents.update_note(socket, content)
  end

  def handle_event("save_note", %{"note" => content}, socket) do
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
        room_code = socket.assigns[:room] && socket.assigns.room.code
        if socket.assigns.user_id && is_binary(thumbnail) && room_code do
          Social.set_photo_thumbnail(
            photo_id_int,
            thumbnail,
            socket.assigns.user_id,
            room_code
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

            # Determine which stream to update based on context
            stream_name = if socket.assigns[:room], do: :items, else: :feed_items
            {:noreply, stream_insert(socket, stream_name, photo_with_type)}
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

  def handle_event("open_devices_modal", _params, socket),
    do: SettingsEvents.open_devices_modal(socket)

  def handle_event("close_devices_modal", _params, socket),
    do: SettingsEvents.close_devices_modal(socket)

  def handle_event("revoke_device", params, socket),
    do: SettingsEvents.revoke_device(socket, params)

  # Device Pairing events
  def handle_event("create_pairing_token", _params, socket) do
    case socket.assigns.current_user do
      nil ->
        {:noreply, put_flash(socket, :error, "Please log in first")}

      user ->
        case Friends.WebAuthn.create_pairing_token(user.id) do
          {:ok, pairing} ->
            # Build pairing URL
            origin = Friends.WebAuthn.origin()
            pairing_url = "#{origin}/pair/#{pairing.token}"

            {:noreply,
             socket
             |> assign(:show_pairing_modal, true)
             |> assign(:pairing_token, pairing.token)
             |> assign(:pairing_url, pairing_url)
             |> assign(:pairing_expires_at, pairing.expires_at)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to create pairing token")}
        end
    end
  end

  def handle_event("close_pairing_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_pairing_modal, false)
     |> assign(:pairing_token, nil)
     |> assign(:pairing_url, nil)}
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

  # Chord Diagram events
  def handle_event("open_chord_diagram", _params, socket) do
    chord_data = FriendsWeb.HomeLive.GraphHelper.build_chord_data(socket.assigns.current_user)
    {:noreply,
     socket
     |> assign(:show_chord_modal, true)
     |> assign(:chord_data, chord_data)}
  end

  def handle_event("open_room_chord", _params, socket) do
    room = socket.assigns[:room]
    if room do
      chord_data = FriendsWeb.HomeLive.GraphHelper.build_room_chord_data(socket.assigns.current_user, room.id)
      {:noreply,
       socket
       |> assign(:show_chord_modal, true)
       |> assign(:chord_data, chord_data)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("close_chord_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_chord_modal, false)
     |> assign(:chord_data, nil)}
  end

  def handle_event("chord_node_clicked", %{"user_id" => user_id}, socket) do
    # Navigate to user profile or open DM
    RoomEvents.open_dm(socket, user_id)
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

  def handle_event("view_full_note", params, socket) do
    NoteEvents.view_full_note(socket, params)
  end

  def handle_event("close_view_note", _params, socket) do
    NoteEvents.close_view_note(socket)
  end

  # Global keyboard handler for accessibility
  def handle_event("handle_keydown", %{"key" => "Escape"}, socket) do
    cond do
      socket.assigns[:show_image_modal] ->
        {:noreply,
         socket
         |> assign(:show_image_modal, false)
         |> assign(:full_image_data, nil)
         |> assign(:current_photo_id, nil)}

      socket.assigns[:show_room_modal] ->
        {:noreply, assign(socket, :show_room_modal, false)}

      socket.assigns[:create_group_modal] ->
        {:noreply, socket |> assign(:create_group_modal, false) |> assign(:new_room_name, "")}

      socket.assigns[:show_settings_modal] ->
        {:noreply,
         socket
         |> assign(:show_settings_modal, false)
         |> assign(:member_invite_search, "")
         |> assign(:member_invite_results, [])}

      socket.assigns[:show_network_modal] ->
        {:noreply,
         socket
         |> assign(:show_network_modal, false)
         |> assign(:friend_search, "")
         |> assign(:friend_search_results, [])}

      socket.assigns[:show_name_modal] ->
        {:noreply, assign(socket, :show_name_modal, false)}

      socket.assigns[:show_note_modal] ->
        {:noreply, socket |> assign(:show_note_modal, false) |> assign(:note_input, "")}

      socket.assigns[:viewing_note] ->
        {:noreply, assign(socket, :viewing_note, nil)}

      socket.assigns[:show_groups_sheet] ->
        {:noreply, assign(socket, :show_groups_sheet, false)}

      socket.assigns[:show_user_menu] ->
        {:noreply, assign(socket, :show_user_menu, false)}

      socket.assigns[:show_contact_sheet] ->
        {:noreply, assign(socket, :show_contact_sheet, false)}

      socket.assigns[:show_create_menu] ->
        {:noreply, assign(socket, :show_create_menu, false)}

      socket.assigns[:show_omnibox] ->
        {:noreply, assign(socket, :show_omnibox, false)}

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

  def handle_event("confirm_trusted_friend", %{"user_id" => user_id_str}, socket) do
    NetworkEvents.confirm_trust(socket, user_id_str)
  end

  def handle_event("open_dm", %{"user_id" => user_id_str}, socket) do
    NetworkEvents.open_dm(socket, user_id_str)
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


  def handle_event("open_invite_modal", _, socket) do
    {:noreply, assign(socket, :show_invite_modal, true)}
  end

  def handle_event("close_invite_modal", _, socket) do
    # Also update the URL to remove ?action=invite so it doesn't reopen on refresh
    room_code = if socket.assigns[:room], do: socket.assigns.room.code, else: nil
    socket = assign(socket, :show_invite_modal, false)
    
    if room_code do
      {:noreply, push_patch(socket, to: ~p"/r/#{room_code}", replace: true)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("set_feed_view", %{"view" => view}, socket) do
    FeedEvents.set_feed_view(socket, view)
  end

  def handle_event("open_room_settings", _, socket) do
    {:noreply, assign(socket, :show_room_settings, true)}
  end

  def handle_event("send_room_voice_note", params, socket) do
    ChatEvents.send_room_voice_note(socket, params)
  end

  def handle_event("send_room_message", params, socket) do
    ChatEvents.send_room_text_message(socket, params)
  end

  # Server-side chat message sending (plain text, no client-side encryption)
  def handle_event("send_chat_message", %{"message" => message}, socket) do
    room = socket.assigns[:room]
    current_user = socket.assigns[:current_user]

    if room && current_user && message != "" do
      # Store as plain text (not encrypted) for now
      result = Friends.Social.Chat.send_room_message(
             room.id,
             current_user.id,
             message,
             "text",
             %{},
             nil
           )
      
      case result do
        {:ok, _message} ->
          {:noreply, assign(socket, :new_chat_message, "")}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Failed to send message")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("update_chat_input", %{"message" => message}, socket) do
    {:noreply, assign(socket, :new_chat_message, message)}
  end

  # Live typing events
  def handle_event("typing", %{"text" => text}, socket) do
    ChatEvents.handle_typing(socket, text)
  end

  def handle_event("stop_typing", _params, socket) do
    ChatEvents.handle_stop_typing(socket)
  end



  def handle_event("toggle_members_panel", _, socket) do
    {:noreply, update(socket, :show_members_panel, &(!&1))}
  end

  def handle_event("close_group_sheet", _, socket) do
    {:noreply, assign(socket, :show_members_panel, false)}
  end

  def handle_event("group_search", %{"value" => query}, socket) do
    {:noreply, assign(socket, :group_search, query)}
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

  # Update chat message input AND broadcast typing
  def handle_event("update_chat_message", %{"value" => text}, socket) do
    room = socket.assigns[:room]
    current_user = socket.assigns[:current_user]

    # Broadcast typing to other users
    if room && current_user && String.length(text) > 0 do
      Phoenix.PubSub.broadcast(
        Friends.PubSub,
        "room:#{room.id}:typing",
        {:user_typing, %{
          user_id: current_user.id,
          username: current_user.username,
          text: text
        }}
      )
    end

    # If text is empty, broadcast stop typing
    if room && current_user && String.length(text) == 0 do
      Phoenix.PubSub.broadcast(
        Friends.PubSub,
        "room:#{room.id}:typing",
        {:user_stopped_typing, %{user_id: current_user.id}}
      )
    end

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
          {:noreply, 
           socket
           |> assign(:new_chat_message, "")
           |> push_event("clear_chat_input", %{})}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to send message")}
      end
    else
      {:noreply, socket}
    end
  end

  # Start voice recording (from hook)
  def handle_event("start_room_voice_recording", _, socket) do
    {:noreply, assign(socket, :recording_voice, true)}
  end

  # Stop voice recording (from hook)
  def handle_event("stop_room_voice_recording", _, socket) do
    {:noreply, assign(socket, :recording_voice, false)}
  end

  # Start voice recording (from button)
  def handle_event("start_room_recording", _, socket) do
    {:noreply,
     socket
     |> assign(:recording_voice, true)
     |> push_event("start_room_voice_recording", %{})}
  end

  # Stop voice recording (from button)
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

  def handle_event("toggle_mobile_chat", _params, socket) do
    ChatEvents.toggle_mobile_chat(socket)
  end

  # Warmth Pulse - send when hovering over content (ambient awareness)
  def handle_event("send_warmth_pulse", %{"type" => item_type, "id" => item_id}, socket) do
    ChatEvents.send_warmth_pulse(socket, item_type, item_id)
  end

  # Walkie-Talkie - hold-to-speak live audio
  def handle_event("walkie_chunk", params, socket) do
    ChatEvents.send_walkie_chunk(socket, params)
  end

  def handle_event("walkie_start", _params, socket) do
    ChatEvents.send_walkie_start(socket)
  end

  def handle_event("walkie_stop", _params, socket) do
    ChatEvents.send_walkie_stop(socket)
  end



  def handle_event("toggle_nav_panel", _params, socket) do
    {:noreply, update(socket, :show_nav_panel, &(!&1))}
  end


  # --- Corner Navigation Events ---

  # --- Bottom Toolbar Events ---

  def handle_event("open_create_menu", _params, socket) do
    {:noreply, assign(socket, :show_create_menu, !socket.assigns[:show_create_menu])}
  end

  def handle_event("close_create_menu", _params, socket) do
    {:noreply, assign(socket, :show_create_menu, false)}
  end

  def handle_event("trigger_photo_upload", _params, socket) do
    # Trigger photo file selector - don't close menu yet (let file selection close it)
    {:noreply, push_event(socket, "trigger_file_input", %{selector: "input[name='feed_photo']"})}
  end

  # --- Omnibox Search Handlers ---

  def handle_event("open_omnibox", _params, socket) do
    {:noreply, 
     socket
     |> assign(:show_omnibox, true)
     |> assign(:omnibox_query, "")
     |> assign(:omnibox_results, %{people: [], groups: [], actions: []})}
  end

  def handle_event("close_omnibox", _params, socket) do
    {:noreply, assign(socket, :show_omnibox, false)}
  end

  def handle_event("omnibox_search", %{"value" => query}, socket) do
    results = perform_omnibox_search(socket, query)
    {:noreply,
     socket
     |> assign(:omnibox_query, query)
     |> assign(:omnibox_results, results)}
  end

  def handle_event("omnibox_select_person", %{"id" => id_str}, socket) do
    # Open DM with this person
    case Integer.parse(id_str) do
      {user_id, _} ->
        if socket.assigns.current_user do
          case Social.get_or_create_dm_room(socket.assigns.current_user.id, user_id) do
            {:ok, room} ->
              {:noreply,
               socket
               |> assign(:show_omnibox, false)
               |> push_navigate(to: ~p"/r/#{room.code}")}
            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Could not open chat")}
          end
        else
          {:noreply, put_flash(socket, :error, "Please log in")}
        end
      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("omnibox_select_group", %{"code" => code}, socket) do
    {:noreply,
     socket
     |> assign(:show_omnibox, false)
     |> push_navigate(to: ~p"/r/#{code}")}
  end

  def handle_event("omnibox_action", %{"action" => action}, socket) do
    socket = assign(socket, :show_omnibox, false)
    
    case action do
      "open_create_group_modal" ->
        {:noreply, assign(socket, :create_group_modal, true)}
      "open_contacts_sheet" ->
        {:noreply, 
         socket
         |> assign(:show_contact_sheet, true)
         |> assign(:contact_mode, :invite_members)}
      "open_profile_sheet" ->
        {:noreply, assign(socket, :show_profile_sheet, true)}
      "show_fullscreen_graph" ->
        {:noreply, 
         socket
         |> assign(:show_fullscreen_graph, true)
         |> assign(:fullscreen_graph_data, FriendsWeb.HomeLive.GraphHelper.build_welcome_graph_data())}
      _ ->
        {:noreply, socket}
    end
  end

  defp perform_omnibox_search(socket, query) do
    query = String.trim(query)
    
    cond do
      query == "" ->
        %{people: [], groups: [], actions: []}
        
      String.starts_with?(query, "@") ->
        # People search
        username_query = String.trim_leading(query, "@")
        people = if username_query != "", do: Social.search_users(username_query, limit: 5), else: []
        %{people: people, groups: [], actions: []}
        
      String.starts_with?(query, "#") ->
        # Group search  
        group_query = String.trim_leading(query, "#")
        groups = if group_query != "" and socket.assigns.current_user do
          Social.search_user_groups(socket.assigns.current_user.id, group_query, limit: 5)
        else
          []
        end
        %{people: [], groups: groups, actions: []}
        
      String.starts_with?(query, "/") ->
        # Actions handled in template
        %{people: [], groups: [], actions: []}
        
      true ->
        # General search - search both people and groups
        people = Social.search_users(query, limit: 3)
        groups = if socket.assigns.current_user do
          Social.search_user_groups(socket.assigns.current_user.id, query, limit: 3)
        else
          []
        end
        %{people: people, groups: groups, actions: []}
    end
  end

  # --- Groups Sheet Events ---

  def handle_event("open_groups_sheet", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_groups_sheet, true)
     |> assign(:show_group_create_form, false)
     |> assign(:group_search_query, "")}
  end

  def handle_event("close_groups_sheet", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_groups_sheet, false)
     |> assign(:show_group_create_form, false)
     |> assign(:group_search_query, "")}
  end

  def handle_event("toggle_group_create_form", _params, socket) do
    {:noreply, assign(socket, :show_group_create_form, !socket.assigns[:show_group_create_form])}
  end

  def handle_event("group_search", %{"value" => query}, socket) do
    results = if query != "" and socket.assigns.current_user do
      Friends.Social.search_user_groups(socket.assigns.current_user.id, query, limit: 20)
    else
      []
    end
    {:noreply,
     socket
     |> assign(:group_search_query, query)
     |> assign(:group_search_results, results)}
  end


  def handle_event("open_create_group", _params, socket) do
    {:noreply, assign(socket, :create_group_modal, true)}
  end

  def handle_event("open_note_modal", _params, socket) do
    {:noreply, assign(socket, :show_note_modal, true)}
  end
  

  
  def handle_event("open_photo_upload", _params, socket) do
    selector =
      if !is_nil(socket.assigns[:room]) do
        "#desktop-upload-form-photo input"
      else
        "#upload-form-feed_photo input"
      end

    {:noreply,
     push_event(socket, "trigger_file_input", %{
       selector: selector
     })}
  end
  
  def handle_event("close_create_group_modal", _params, socket) do
    {:noreply, assign(socket, :create_group_modal, false)}
  end

  # Hidden feature: Long-press nav orb reveals fullscreen graph
  def handle_event("show_fullscreen_graph", _params, socket) do
    # Subscribe to network events for live graph updates
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Friends.PubSub, "friends:global")
      Phoenix.PubSub.subscribe(Friends.PubSub, "friends:new_users")
    end

    graph_data = FriendsWeb.HomeLive.GraphHelper.build_welcome_graph_data()
    {:noreply,
     socket
     |> assign(:show_fullscreen_graph, true)
     |> assign(:fullscreen_graph_data, graph_data)}
  end

  def handle_event("close_fullscreen_graph", _params, socket) do
    # Unsubscribe from network events
    Phoenix.PubSub.unsubscribe(Friends.PubSub, "friends:global")
    Phoenix.PubSub.unsubscribe(Friends.PubSub, "friends:new_users")

    {:noreply,
     socket
     |> assign(:show_fullscreen_graph, false)
     |> assign(:fullscreen_graph_data, nil)}
  end

  # Check connection status with another user (for graph context menu)
  def handle_event("check_friendship_status", %{"user_id" => user_id_str}, socket) do
    case Integer.parse(user_id_str) do
      {user_id, _} ->
        current_user = socket.assigns.current_user
        
        if current_user do
          friendship = Social.get_friendship(current_user.id, user_id) || 
                       Social.get_friendship(user_id, current_user.id)
          
          status = case friendship do
            %{status: "accepted"} -> "connected"
            %{status: "pending"} -> "pending"
            _ -> "none"
          end
          
          {:reply, %{status: status}, socket}
        else
          {:reply, %{status: "none"}, socket}
        end
        
      _ ->
        {:reply, %{status: "none"}, socket}
    end
  end

  # Handle action from graph context menu
  def handle_event("graph_node_action", %{"user_id" => user_id_str, "action" => action}, socket) do
    case Integer.parse(user_id_str) do
      {user_id, _} ->
        current_user = socket.assigns.current_user
        
        if current_user && user_id != current_user.id do
          case action do
            "message" ->
              # Open DM with this user
              case Social.get_or_create_dm_room(current_user.id, user_id) do
                {:ok, room} ->
                  {:noreply,
                   socket
                   |> assign(:show_fullscreen_graph, false)
                   |> assign(:fullscreen_graph_data, nil)
                   |> push_navigate(to: ~p"/r/#{room.code}")}
                _ ->
                  {:noreply, socket}
              end
            
            "add_friend" ->
              # Send friend request
              case Social.add_friend(current_user.id, user_id) do
                {:ok, _} ->
                  {:noreply, put_flash(socket, :info, "Connection request sent!")}
                {:error, :already_friends} ->
                  {:noreply, put_flash(socket, :info, "Already connected!")}
                {:error, :request_already_sent} ->
                  {:noreply, put_flash(socket, :info, "Request already sent")}
                _ ->
                  {:noreply, socket}
              end
            
            "profile" ->
              # Show profile sheet
              user = Social.get_user(user_id)
              {:noreply,
               socket
               |> assign(:show_fullscreen_graph, false)
               |> assign(:fullscreen_graph_data, nil)
               |> assign(:show_profile_sheet, true)
               |> assign(:viewing_user, user)}
            
            _ ->
              {:noreply, socket}
          end
        else
          {:noreply, socket}
        end
        
      _ ->
        {:noreply, socket}
    end
  end


  # --- Graph Events ---

  # Send friend request from graph by clicking on 2nd degree nodes
  def handle_event("add_friend_from_graph", %{"user_id" => user_id_str}, socket) do
    case Integer.parse(user_id_str) do
      {user_id, _} ->
        current_user = socket.assigns.current_user
        if current_user do
          case Social.add_friend(current_user.id, user_id) do
            {:ok, _} ->
              # Refresh graph data and outgoing requests
              graph_data = FriendsWeb.HomeLive.GraphHelper.build_graph_data(current_user)
              outgoing = Social.list_sent_friend_requests(current_user.id)
              {:noreply,
               socket
               |> assign(:graph_data, graph_data)
               |> assign(:outgoing_friend_requests, outgoing)
               |> put_flash(:info, "Connection request sent!")}
            {:error, :cannot_friend_self} ->
              {:noreply, put_flash(socket, :error, "Can't add yourself")}
            {:error, :already_friends} ->
              {:noreply, put_flash(socket, :info, "Already connected!")}
            {:error, :request_already_sent} ->
              {:noreply, put_flash(socket, :info, "Request already sent")}
            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Could not send request")}
          end
        else
          {:noreply, socket}
        end
      _ ->
        {:noreply, put_flash(socket, :error, "Invalid user")}
    end
  end

  # --- Contact Search Events ---



  def handle_event("send_friend_request", %{"user_id" => user_id_str}, socket) do
    case Integer.parse(user_id_str) do
      {user_id, _} ->
        current_user = socket.assigns.current_user
        if current_user do
          case Social.add_friend(current_user.id, user_id) do
            {:ok, _} ->
              # Refresh outgoing requests list
              outgoing = Social.list_sent_friend_requests(current_user.id)
              {:noreply,
               socket
               |> assign(:outgoing_friend_requests, outgoing)
               |> assign(:show_contact_sheet, false)
               |> assign(:contact_sheet_search, "")
               |> assign(:contact_search_results, [])
               |> put_flash(:info, "Connection request sent!")}
            {:error, :cannot_friend_self} ->
              {:noreply, put_flash(socket, :error, "Can't add yourself")}
            {:error, :already_friends} ->
              {:noreply, put_flash(socket, :error, "Already connected")}
            {:error, :request_already_sent} ->
              {:noreply, put_flash(socket, :error, "Request already sent")}
            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Could not send request")}
          end
        else
          {:noreply, socket}
        end
      _ ->
        {:noreply, put_flash(socket, :error, "Invalid user")}
    end
  end

  def handle_event("add_room_member", %{"user_id" => user_id_str, "room_id" => room_id_str}, socket) do
    with {user_id, _} <- Integer.parse(user_id_str),
         {room_id, _} <- Integer.parse(room_id_str),
         current_user when not is_nil(current_user) <- socket.assigns.current_user do
      case Social.add_room_member(room_id, user_id, current_user.id) do
        {:ok, _member} ->
          # Refresh room members
          room = socket.assigns.room
          members = Social.list_room_members(room.id)
          {:noreply,
           socket
           |> assign(:room_members, members)
           |> assign(:show_contact_sheet, false)
           |> assign(:contact_sheet_search, "")
           |> assign(:contact_search_results, [])
           |> put_flash(:info, "Member added!")}
        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not add member")}
      end
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Invalid request")}
    end
  end

  def handle_event("remove_contact", %{"user_id" => user_id_str}, socket) do
    case Integer.parse(user_id_str) do
      {user_id, _} ->
        current_user = socket.assigns.current_user
        if current_user do
          case Social.remove_friend(current_user.id, user_id) do
            {:ok, _} ->
              # Refresh friends list
              friends = Social.list_friends(current_user.id)
              {:noreply,
               socket
               |> assign(:friends, friends)
               |> put_flash(:info, "Removed")}
            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Could not remove")}
          end
        else
          {:noreply, socket}
        end
      _ ->
        {:noreply, put_flash(socket, :error, "Invalid user")}
    end
  end

  def handle_event("cancel_request", %{"user_id" => user_id_str}, socket) do
    case Integer.parse(user_id_str) do
      {user_id, _} ->
        current_user = socket.assigns.current_user
        if current_user do
          # Try to remove friend request first (most common case)
          Social.remove_friend(current_user.id, user_id)
          
          # Refresh both friend and trust requests
          sent_friends = Social.list_sent_friend_requests(current_user.id)
          sent_trust = Social.list_sent_trust_requests(current_user.id)
          
          {:noreply,
           socket
           |> assign(:outgoing_friend_requests, sent_friends)
           |> assign(:outgoing_trust_requests, sent_trust)
           |> put_flash(:info, "Request cancelled")}
        else
          {:noreply, socket}
        end
      _ ->
        {:noreply, put_flash(socket, :error, "Invalid user")}
    end
  end

  def handle_event("accept_friend_request", %{"user_id" => user_id_str}, socket) do
    case Integer.parse(user_id_str) do
      {user_id, _} ->
        current_user = socket.assigns.current_user
        if current_user do
          case Social.accept_friend(current_user.id, user_id) do
            {:ok, _} ->
              # Refresh friends and pending requests
              friends = Social.list_friends(current_user.id)
              pending_requests = Social.list_friend_requests(current_user.id)
              {:noreply,
               socket
               |> assign(:friends, friends)
               |> assign(:pending_requests, pending_requests)
               |> put_flash(:info, "Connected!")}
            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Could not accept request")}
          end
        else
          {:noreply, socket}
        end
      _ ->
        {:noreply, put_flash(socket, :error, "Invalid user")}
    end
  end

  def handle_event("decline_friend_request", %{"user_id" => user_id_str}, socket) do
    case Integer.parse(user_id_str) do
      {user_id, _} ->
        current_user = socket.assigns.current_user
        if current_user do
          # Declining a friend request removes the pending friendship
          case Social.remove_friend(current_user.id, user_id) do
            {:ok, _} ->
              # Refresh pending requests
              pending_requests = Social.list_friend_requests(current_user.id)
              {:noreply,
               socket
               |> assign(:pending_requests, pending_requests)
               |> put_flash(:info, "Request declined")}
            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Could not decline request")}
          end
        else
          {:noreply, socket}
        end
      _ ->
        {:noreply, put_flash(socket, :error, "Invalid user")}
    end
  end

  def handle_event("remove_trusted_friend", %{"user_id" => user_id_str}, socket) do
    case Integer.parse(user_id_str) do
      {user_id, _} ->
        current_user = socket.assigns.current_user
        if current_user do
          case Social.remove_trusted_friend(current_user.id, user_id) do
            :ok ->
              # Refresh trusted friends list
              trusted = Social.list_trusted_friends(current_user.id)
              {:noreply,
               socket
               |> assign(:trusted_friends, trusted)
               |> put_flash(:info, "Removed from recovery contacts")}
            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Could not remove")}
          end
        else
          {:noreply, socket}
        end
      _ ->
        {:noreply, put_flash(socket, :error, "Invalid user")}
    end
  end



  def handle_event("decline_trusted_friend", %{"user_id" => user_id_str}, socket) do
    case Integer.parse(user_id_str) do
      {requester_id, _} ->
        current_user = socket.assigns.current_user
        if current_user do
          # Declining just removes the pending request (same as requester's cancel)
          case Social.decline_trust_request(current_user.id, requester_id) do
            :ok ->
              incoming = Social.list_pending_trust_requests(current_user.id)
              {:noreply,
               socket
               |> assign(:incoming_trust_requests, incoming)
               |> put_flash(:info, "Request declined")}
            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Could not decline")}
          end
        else
          {:noreply, socket}
        end
      _ ->
        {:noreply, put_flash(socket, :error, "Invalid user")}
    end
  end

  # --- Groups Sheet Events ---

  def handle_event("open_groups_sheet", _, socket) do
    {:noreply,
     socket
     |> assign(show_groups_sheet: true, group_search_query: "")
     |> assign(:show_user_menu, false)
     |> assign(:show_profile_sheet, false)}
  end

  def handle_event("close_groups_sheet", _, socket) do
    {:noreply, assign(socket, show_groups_sheet: false)}
  end

  # --- Contact/People Sheet Events ---

  def handle_event("open_contacts_sheet", _, socket) do
    {:noreply,
     socket
     |> assign(:show_contact_sheet, true)
     |> assign(:show_user_menu, false)
     |> assign(:show_profile_sheet, false)
     |> assign(:contact_mode, :list_contacts)
     |> assign(:contact_sheet_search, "")
     |> assign(:contact_search_results, [])}
  end

  def handle_event("open_contact_search", params, socket) do
    mode = params["mode"] || "list_contacts"
    {:noreply,
     socket
     |> assign(:show_contact_sheet, true)
     |> assign(:show_header_dropdown, false)
     |> assign(:show_user_dropdown, false)
     |> assign(:show_user_menu, false)
     |> assign(:show_profile_sheet, false)
     |> assign(:contact_mode, mode)
     |> assign(:contact_sheet_search, "")
     |> assign(:contact_search_results, [])}
  end

  def handle_event("close_contact_search", _, socket) do
    {:noreply, assign(socket, :show_contact_sheet, false)}
  end
  
  def handle_event("contact_search", %{"value" => query}, socket) do
    query = String.trim(query)
    # Filter local friends first for instant feedback (especially for invite mode)
    friends = socket.assigns[:friends] || []
    
    local_results = Enum.filter(friends, fn friend -> 
      # Handle both simple friend maps and loaded user structs
      user = Map.get(friend, :user) || friend
      username = user.username || ""
      String.contains?(String.downcase(username), String.downcase(query))
    end) |> Enum.map(fn f -> Map.get(f, :user) || f end)

    # Search globally like in network modal if query is long enough
    global_results = if String.length(query) >= 2 do
      Social.search_users(query, socket.assigns.current_user.id)
    else
      []
    end
    
    # Merge results, prioritizing friends (local results)
    # Use MapSet or user ID to unique
    results = Enum.uniq_by(local_results ++ global_results, & &1.id)
    
    {:noreply, 
     socket
     |> assign(:contact_sheet_search, query)
     |> assign(:contact_search_results, results)}
  end

  def handle_event("group_search", %{"value" => query}, socket) do
    query = String.downcase(query)
    groups = socket.assigns.user_private_rooms
    
    results = Enum.filter(groups, fn group ->
      name = group.name || group.code || ""
      String.contains?(String.downcase(name), query)
    end)

    {:noreply, 
     socket 
     |> assign(:group_search_query, query)
     |> assign(:group_search_results, results)}
  end

  # --- Welcome Graph Events ---

  # Skip welcome graph view and show regular feed
  def handle_event("skip_welcome_graph", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_welcome_graph, false)
     |> assign(:welcome_graph_data, nil)}
  end

  # --- Global User Menu & Sheet Handlers ---

  def handle_event("toggle_user_menu", _params, socket) do
    {:noreply, assign(socket, :show_user_menu, !Map.get(socket.assigns, :show_user_menu, false))}
  end

  def handle_event("open_profile_sheet", _params, socket) do
    {:noreply, assign(socket, :show_profile_sheet, true)}
  end

  def handle_event("close_profile_sheet", _params, socket) do
    {:noreply, assign(socket, :show_profile_sheet, false)}
  end

  def handle_event("toggle_members_panel", _params, socket) do
    {:noreply, 
     socket
     |> assign(:show_group_sheet, !socket.assigns[:show_group_sheet])
     |> assign(:group_search, "")}
  end

  def handle_event("open_invite_sheet", _params, socket) do
    {:noreply, 
     socket
     |> assign(:show_group_sheet, true)
     |> assign(:group_search, "")}
  end

  def handle_event("close_group_sheet", _params, socket) do
    {:noreply, 
     socket
     |> assign(:show_group_sheet, false)
     |> assign(:group_search, "")}
  end

  def handle_event("invite_friend_to_room", %{"friend_id" => friend_id}, socket) do
    RoomEvents.invite_to_room(socket, friend_id)
  end

  def handle_event("open_member_menu", %{"member_id" => member_id_str}, socket) do
    case Integer.parse(member_id_str) do
      {member_id, _} ->
        {:noreply, assign(socket, :context_menu_member_id, member_id)}
      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("close_member_menu", _params, socket) do
    {:noreply, assign(socket, :context_menu_member_id, nil)}
  end

  def handle_event("make_admin", %{"user_id" => user_id_str}, socket) do
    case Integer.parse(user_id_str) do
      {user_id, _} ->
        room = socket.assigns.room
        if room && room.owner_id == socket.assigns.current_user.id do
          Social.update_member_role(room.id, user_id, "admin")
          room_members = Social.list_room_members(room.id)
          {:noreply, assign(socket, :room_members, room_members)}
        else
          {:noreply, socket}
        end
      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("remove_admin", %{"user_id" => user_id_str}, socket) do
    case Integer.parse(user_id_str) do
      {user_id, _} ->
        room = socket.assigns.room
        if room && room.owner_id == socket.assigns.current_user.id do
          Social.update_member_role(room.id, user_id, "member")
          room_members = Social.list_room_members(room.id)
          {:noreply, assign(socket, :room_members, room_members)}
        else
          {:noreply, socket}
        end
      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("remove_member", %{"user_id" => user_id_str}, socket) do
    case Integer.parse(user_id_str) do
      {user_id, _} ->
        room = socket.assigns.room
        current_user = socket.assigns.current_user
        
        # Check if user can remove members (owner or admin)
        is_owner = room && room.owner_id == current_user.id
        current_member = Enum.find(socket.assigns[:room_members] || [], fn m -> m.user_id == current_user.id end)
        is_admin = current_member && current_member.role == "admin"
        
        if is_owner or is_admin do
          Social.remove_room_member(room.id, user_id)
          room_members = Social.list_room_members(room.id)
          {:noreply, assign(socket, :room_members, room_members)}
        else
          {:noreply, socket}
        end
      _ ->
        {:noreply, socket}
    end
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

  # Pin/Unpin broadcasts - just reload items to show updated pinned state
  def handle_info({:photo_pinned, _data}, socket), do: {:noreply, socket}
  def handle_info({:photo_unpinned, _data}, socket), do: {:noreply, socket}
  def handle_info({:note_pinned, _data}, socket), do: {:noreply, socket}
  def handle_info({:note_unpinned, _data}, socket), do: {:noreply, socket}

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

  def handle_info({:photo_updated, photo}, socket) do
    PubSubHandlers.handle_photo_updated(socket, photo)
  end

  # Handle new room message from PubSub
  def handle_info({:new_room_message, message}, socket) do
    PubSubHandlers.handle_new_room_message(socket, message)
  end

  def handle_info({:note_deleted, %{id: id}}, socket) do
    PubSubHandlers.handle_note_deleted(socket, id)
  end

  def handle_info(%{event: "presence_diff", payload: diff}, socket) do
    # Handle room presence (viewers in room)
    {:noreply, socket1} = PubSubHandlers.handle_presence_diff(socket, diff)
    # Also handle global presence (online friend indicators)
    PubSubHandlers.handle_global_presence_diff(socket1, diff)
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

  # Handle photo deletion - update feed stream live
  def handle_info({:photo_deleted, %{id: photo_id}}, socket) do
    if socket.assigns[:feed_item_count] do
      # Public feed context
      {:noreply,
       socket
       |> assign(:feed_item_count, max(0, socket.assigns.feed_item_count - 1))
       |> stream_delete(:feed_items, %{id: photo_id, unique_id: "photo-#{photo_id}", type: :photo})}
    else
      # Room context
      {:noreply,
       socket
       |> assign(:item_count, max(0, (socket.assigns[:item_count] || 0) - 1))
       |> stream_delete(:items, %{id: photo_id, unique_id: "photo-#{photo_id}"})}
    end
  end

  # Handle note deletion - update feed stream live
  def handle_info({:note_deleted, %{id: note_id}}, socket) do
    if socket.assigns[:feed_item_count] do
      {:noreply,
       socket
       |> assign(:feed_item_count, max(0, socket.assigns.feed_item_count - 1))
       |> stream_delete(:feed_items, %{id: note_id, unique_id: "note-#{note_id}", type: :note})}
    else
      {:noreply,
       socket
       |> assign(:item_count, max(0, (socket.assigns[:item_count] || 0) - 1))
       |> stream_delete(:items, %{id: note_id, unique_id: "note-#{note_id}"})}
    end
  end

  # Handle incoming friend request - someone sent us a request
  def handle_info({:friend_request, _friendship}, socket) do
    if socket.assigns.current_user do
      pending_requests = Social.list_friend_requests(socket.assigns.current_user.id)
      {:noreply, assign(socket, :pending_requests, pending_requests)}
    else
      {:noreply, socket}
    end
  end

  # --- New Real-time Social Event Handlers ---
  
  # Handle when someone sends you a connection request (live update)
  def handle_info({:connection_request_received, from_user_id}, socket) do
    PubSubHandlers.handle_connection_request_received(socket, from_user_id)
  end

  # Handle when someone accepts your connection request (live update)
  def handle_info({:connection_accepted, by_user_id}, socket) do
    PubSubHandlers.handle_connection_accepted(socket, by_user_id)
  end

  # Handle when someone sends you a trust/recovery request (live update)
  def handle_info({:trust_request_received, from_user_id}, socket) do
    PubSubHandlers.handle_trust_request_received(socket, from_user_id)
  end

  # Handle when someone confirms your trust request (live update)
  def handle_info({:trust_confirmed, by_user_id}, socket) do
    PubSubHandlers.handle_trust_confirmed(socket, by_user_id)
  end

  # Handle new user joining (for live graph updates)
  def handle_info({:new_user_joined, user_data}, socket) do
    # Push to graph when feed is empty (graph shows as empty state)
    if socket.assigns[:feed_item_count] == 0 do
      {:noreply,
       push_event(socket, "welcome_new_user", %{
         id: user_data.id,
         username: user_data.username,
         display_name: user_data.display_name || user_data.username
       })}
    else
      {:noreply, socket}
    end
  end

  # Handle friendship events (when a friend is accepted or removed)
  def handle_info({:friend_accepted, friendship}, socket) do
    # Refresh the graph data, friends list, and private rooms when a friendship changes
    if socket.assigns.current_user do
      graph_data = FriendsWeb.HomeLive.GraphHelper.build_graph_data(socket.assigns.current_user)
      private_rooms = Social.list_user_rooms(socket.assigns.current_user.id)
      friends = Social.list_friends(socket.assigns.current_user.id)
      pending_requests = Social.list_friend_requests(socket.assigns.current_user.id)

      socket =
        socket
        |> assign(:graph_data, graph_data)
        |> assign(:user_private_rooms, private_rooms)
        |> assign(:friends, friends)
        |> assign(:pending_requests, pending_requests)
        
      # If feed is empty (graph shown as empty state), push live update for new connection
      socket = if socket.assigns[:feed_item_count] == 0 do
        socket
        |> push_event("welcome_new_connection", %{
          from_id: friendship.user_id,
          to_id: friendship.friend_user_id
        })
      else
        socket
      end


      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:friend_removed, friendship}, socket) do
    # Refresh the graph data when a friendship is removed
    if socket.assigns.current_user do
      graph_data = FriendsWeb.HomeLive.GraphHelper.build_graph_data(socket.assigns.current_user)

      socket = assign(socket, :graph_data, graph_data)
      
      # If feed is empty (graph shown as empty state), push live update for removed connection
      socket = if socket.assigns[:feed_item_count] == 0 do
        socket
        |> push_event("welcome_connection_removed", %{
          from_id: friendship.user_id,
          to_id: friendship.friend_user_id
        })
      else
        socket
      end


      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  # --- Live Typing Events ---

  def handle_info({:user_typing, payload}, socket) do
    PubSubHandlers.handle_user_typing(socket, payload)
  end

  def handle_info({:user_stopped_typing, payload}, socket) do
    PubSubHandlers.handle_user_stopped_typing(socket, payload)
  end

  # --- Warmth Pulse Events (Ambient Awareness) ---

  def handle_info({:warmth_pulse, payload}, socket) do
    ChatEvents.handle_warmth_pulse(socket, payload)
  end

  def handle_info({:clear_warmth, key}, socket) do
    ChatEvents.clear_warmth(socket, key)
  end

  # --- Viewing Indicators (Shared Attention) ---

  def handle_info({:user_viewing, payload}, socket) do
    ChatEvents.handle_viewing(socket, payload)
  end

  def handle_info({:user_stopped_viewing, payload}, socket) do
    ChatEvents.handle_stopped_viewing(socket, payload)
  end

  # --- Walkie-Talkie Events (Live Audio) ---

  def handle_info({:walkie_chunk, payload}, socket) do
    ChatEvents.handle_walkie_chunk(socket, payload)
  end

  def handle_info({:walkie_start, payload}, socket) do
    ChatEvents.handle_walkie_start(socket, payload)
  end

  def handle_info({:walkie_stop, payload}, socket) do
    ChatEvents.handle_walkie_stop(socket, payload)
  end

  # --- Group Invite Events (Real-time) ---

  def handle_info({:group_invite_received, invite_info}, socket) do
    PubSubHandlers.handle_group_invite_received(socket, invite_info)
  end

end
