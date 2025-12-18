defmodule FriendsWeb.HomeLive do
  use FriendsWeb, :live_view

  alias Friends.Social

  import FriendsWeb.HomeLive.Helpers
  import FriendsWeb.HomeLive.Components.RoomComponents
  import FriendsWeb.HomeLive.Components.SettingsComponents
  import FriendsWeb.HomeLive.Components.ChatComponents
  import FriendsWeb.HomeLive.Components.InviteComponents
  import FriendsWeb.HomeLive.Components.DrawerComponents
  import FriendsWeb.HomeLive.Components.FluidRoomComponents
  import FriendsWeb.HomeLive.Components.FluidFeedComponents
  import FriendsWeb.HomeLive.Components.FluidModalComponents
  import FriendsWeb.HomeLive.Components.FluidContactComponents
  import FriendsWeb.HomeLive.Components.FluidGroupComponents
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

  def handle_event("toggle_groups", _params, socket) do
    {:noreply, assign(socket, :groups_collapsed, !socket.assigns[:groups_collapsed])}
  end

  def handle_event("toggle_nav_drawer", _params, socket) do
    {:noreply, assign(socket, :show_nav_drawer, !socket.assigns[:show_nav_drawer])}
  end

  def handle_event("toggle_graph_drawer", _params, socket) do
    {:noreply, assign(socket, :show_graph_drawer, !socket.assigns[:show_graph_drawer])}
  end

  def handle_event("toggle_fab", _params, socket) do
    {:noreply, assign(socket, :fab_expanded, !socket.assigns[:fab_expanded])}
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

  def handle_event("delete_photo", %{"id" => id}, socket) do
    PhotoEvents.delete_photo(socket, id)
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
  def handle_event("close_note_modal", _params, socket), do: NoteEvents.close_note_modal(socket)
  
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

  def handle_event("view_full_note", params, socket) do
    NoteEvents.view_full_note(socket, params)
  end

  def handle_event("close_view_note", _params, socket) do
    NoteEvents.close_view_note(socket)
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

  def handle_event("toggle_mobile_chat", _params, socket) do
    ChatEvents.toggle_mobile_chat(socket)
  end



  def handle_event("toggle_chat_expanded", _params, socket) do
    ChatEvents.toggle_chat_expanded(socket)
  end

  def handle_event("toggle_nav_panel", _params, socket) do
    {:noreply, update(socket, :show_nav_panel, &(!&1))}
  end



  # --- Corner Navigation Events ---

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
    graph_data = FriendsWeb.HomeLive.GraphHelper.build_welcome_graph_data()
    {:noreply,
     socket
     |> assign(:show_fullscreen_graph, true)
     |> assign(:fullscreen_graph_data, graph_data)}
  end

  def handle_event("close_fullscreen_graph", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_fullscreen_graph, false)
     |> assign(:fullscreen_graph_data, nil)}
  end

  # --- Contact Search Events ---

  def handle_event("open_contact_search", %{"mode" => mode}, socket) do
    mode_atom = case mode do
      "add_member" -> :add_member
      _ -> :add_contact
    end
    {:noreply,
     socket
     |> assign(:show_contact_search, true)
     |> assign(:contact_search_mode, mode_atom)
     |> assign(:contact_search_query, "")
     |> assign(:contact_search_results, [])
     |> assign(:show_user_menu, false)}
  end

  def handle_event("close_contact_search", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_contact_search, false)
     |> assign(:contact_search_query, "")
     |> assign(:contact_search_results, [])}
  end

  def handle_event("contact_search", %{"value" => query}, socket) do
    query = String.trim(query)
    current_user = socket.assigns.current_user

    results = if String.length(query) >= 2 and current_user do
      case socket.assigns[:contact_search_mode] do
        :add_member ->
          # Search only from user's existing contacts/friends
          Social.search_friends(current_user.id, query)
        _ ->
          # Search all users
          Social.search_users(query, current_user.id)
      end
    else
      []
    end

    {:noreply,
     socket
     |> assign(:contact_search_query, query)
     |> assign(:contact_search_results, results)}
  end

  def handle_event("clear_contact_search", _params, socket) do
    {:noreply,
     socket
     |> assign(:contact_search_query, "")
     |> assign(:contact_search_results, [])}
  end

  def handle_event("send_friend_request", %{"user_id" => user_id_str}, socket) do
    case Integer.parse(user_id_str) do
      {user_id, _} ->
        current_user = socket.assigns.current_user
        if current_user do
          case Social.add_trusted_friend(current_user.id, user_id) do
            {:ok, _} ->
              {:noreply,
               socket
               |> assign(:show_contact_search, false)
               |> assign(:contact_search_query, "")
               |> assign(:contact_search_results, [])
               |> put_flash(:info, "Friend request sent!")}
            {:error, :cannot_trust_self} ->
              {:noreply, put_flash(socket, :error, "Can't add yourself")}
            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Already requested")}
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
           |> assign(:show_contact_search, false)
           |> assign(:contact_search_query, "")
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
          case Social.cancel_trust_request(current_user.id, user_id) do
            :ok ->
              # Refresh outgoing requests
              outgoing = Social.list_sent_trust_requests(current_user.id)
              {:noreply,
               socket
               |> assign(:outgoing_trust_requests, outgoing)
               |> put_flash(:info, "Request cancelled")}
            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Could not cancel")}
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
    {:noreply, assign(socket, show_groups_sheet: true, group_search_query: "")}
  end

  def handle_event("close_groups_sheet", _, socket) do
    {:noreply, assign(socket, show_groups_sheet: false)}
  end

  def handle_event("group_search", %{"value" => query}, socket) do
    query = String.downcase(query)
    groups = socket.assigns.user_private_rooms
    
    results = Enum.filter(groups, fn group ->
      String.contains?(String.downcase(group.name), query)
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

  # Handle friendship events (when a friend is accepted or removed)
  def handle_info({:friend_accepted, friendship}, socket) do
    # Refresh the graph data and private rooms when a friendship changes
    if socket.assigns.current_user do
      graph_data = FriendsWeb.HomeLive.GraphHelper.build_graph_data(socket.assigns.current_user)
      private_rooms = Social.list_user_rooms(socket.assigns.current_user.id)

      socket =
        socket
        |> assign(:graph_data, graph_data)
        |> assign(:user_private_rooms, private_rooms)
        
      # If welcome graph is displayed, push live update for new connection
      socket = if socket.assigns[:show_welcome_graph] do
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
      
      # If welcome graph is displayed, push live update for removed connection
      socket = if socket.assigns[:show_welcome_graph] do
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

  # --- Helpers ---
  # Note: navigate_photo/2 is imported from FriendsWeb.HomeLive.Helpers



  # --- Global User Menu & Sheet Handlers ---

  def handle_event("toggle_user_menu", _params, socket) do
    {:noreply, assign(socket, :show_user_menu, !socket.assigns[:show_user_menu])}
  end

  def handle_event("toggle_members_panel", _params, socket) do
    {:noreply, assign(socket, :show_members_panel, !socket.assigns[:show_members_panel])}
  end

  def handle_event("open_invite_sheet", _params, socket) do
    {:noreply, 
     socket
     |> assign(:show_members_panel, false) 
     |> assign(:show_contact_sheet, true) 
     |> assign(:contact_mode, :invite)
     |> assign(:contact_sheet_search, "")}
  end

  def handle_event("invite_friend_to_room", %{"friend_id" => friend_id}, socket) do
    RoomEvents.invite_to_room(socket, friend_id)
  end

end
