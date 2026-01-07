defmodule FriendsWeb.HomeLive.PubSubHandlers do
  @moduledoc """
  Event handlers for PubSub messages (handle_info).
  """
  import Phoenix.Component
  import Phoenix.LiveView
  import FriendsWeb.HomeLive.Helpers
  alias Friends.Social
  require Logger

  # --- Room Creation ---

  def handle_room_created(socket, _room) do
    case socket.assigns.current_user do
      nil ->
        {:noreply, socket}

      user ->
        private_rooms = Social.list_user_rooms(user.id)
        {:noreply, assign(socket, :user_private_rooms, private_rooms)}
    end
  end

  def handle_public_room_created(socket, _room) do
    public_rooms = Social.list_public_rooms()
    {:noreply, assign(socket, :public_rooms, public_rooms)}
  end

  # --- Room Items (Photos/Notes) ---

  def handle_new_photo(socket, photo) do
    Logger.info("PubSubHandlers: Received new photo ID #{photo.id} from user #{photo.user_id} (My user: #{socket.assigns.user_id})")
    
    # Check if this photo should be ignored (was just uploaded by this socket as part of a batch)
    ignored_ids = socket.assigns[:uploaded_ids_to_ignore] || MapSet.new()
    
    if MapSet.member?(ignored_ids, photo.id) do
      {:noreply, socket}
    else
      # Only insert if not from self (optimistic UI handles self)
      if photo.user_id != socket.assigns.user_id do
        photo_with_type =
          photo
          |> Map.from_struct()
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
  end

  def handle_new_note(socket, note) do
    if note.user_id != socket.assigns.user_id do
      note_with_type =
        note
        |> Map.from_struct()
        |> Map.put(:type, :note)
        |> Map.put(:unique_id, "note-#{note.id}")

      {:noreply,
       socket
       |> assign(:item_count, socket.assigns.item_count + 1)
       |> stream_insert(:items, note_with_type, at: 0)}
    else
      {:noreply, socket}
    end
  end

  def handle_photo_deleted(socket, id) do
    if socket.assigns[:feed_item_count] do
      # Feed context
      {:noreply,
       socket
       |> assign(:feed_item_count, max(0, socket.assigns.feed_item_count - 1))
       |> assign(:photo_order, remove_photo_from_order(socket.assigns[:photo_order], id))
       |> stream_delete(:feed_items, %{id: id, unique_id: "photo-#{id}", type: :photo})}
    else
      # Room context
      {:noreply,
       socket
       |> assign(:item_count, max(0, (socket.assigns[:item_count] || 0) - 1))
       |> assign(:photo_order, remove_photo_from_order(socket.assigns[:photo_order], id))
       |> stream_delete(:items, %{id: id, unique_id: "photo-#{id}"})}
    end
  end

  def handle_note_deleted(socket, id) do
    if socket.assigns[:feed_item_count] do
      {:noreply,
       socket
       |> assign(:feed_item_count, max(0, socket.assigns.feed_item_count - 1))
       |> stream_delete(:feed_items, %{id: id, unique_id: "note-#{id}", type: :note})}
    else
      {:noreply,
       socket
       |> assign(:item_count, max(0, (socket.assigns[:item_count] || 0) - 1))
       |> stream_delete(:items, %{id: id, unique_id: "note-#{id}"})}
    end
  end

  def handle_photo_thumbnail_updated(socket, photo_id, thumbnail_data) do
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

        # Update the appropriate stream based on photo type and current view
        socket =
          cond do
            photo.room_id && socket.assigns[:item_count] ->
              # Room photo, and we are in a room view (implied by item_count)
              stream_insert(socket, :items, photo_with_type)

            is_nil(photo.room_id) && socket.assigns[:feed_item_count] ->
              # Public photo, and we are in a view showing feed (implied by feed_item_count)
              stream_insert(socket, :feed_items, photo_with_type)

            true ->
              socket
          end

        {:noreply, socket}
    end
  end

  def handle_photo_updated(socket, photo) do
    # Skip photos that are part of a batch/gallery - they shouldn't appear as individual items
    if photo.batch_id do
      {:noreply, socket}
    else
      photo_with_type =
        photo
        |> Map.from_struct()
        |> Map.put(:type, :photo)
        |> Map.put(:unique_id, "photo-#{photo.id}")

      # Update the appropriate stream based on photo type and current view
      socket =
        cond do
          photo.room_id && socket.assigns[:item_count] ->
            stream_insert(socket, :items, photo_with_type)

          is_nil(photo.room_id) && socket.assigns[:feed_item_count] ->
            stream_insert(socket, :feed_items, photo_with_type)

          true ->
            socket
        end

      {:noreply, socket}
    end
  end

  # --- Chat ---

  def handle_new_room_message(socket, message) do
    # When a message is sent, clear typing indicator for that user
    typing_users = socket.assigns[:typing_users] || %{}
    updated_typing = Map.delete(typing_users, message.sender_id)
    socket = assign(socket, :typing_users, updated_typing)

    if socket.assigns.show_chat_panel or socket.assigns.room_tab == "chat" do
      messages = socket.assigns.room_messages ++ [message]
      {:noreply, assign(socket, :room_messages, messages)}
    else
      {:noreply, socket}
    end
  end

  # --- Live Typing ---

  def handle_user_typing(socket, %{user_id: user_id, username: username, text: text}) do
    current_user = socket.assigns[:current_user]

    # Ignore own typing
    if current_user && user_id == current_user.id do
      {:noreply, socket}
    else
      # Update typing_users map
      typing_users = socket.assigns[:typing_users] || %{}
      updated = Map.put(typing_users, user_id, %{
        username: username,
        text: text,
        timestamp: System.system_time(:millisecond)
      })

      {:noreply, assign(socket, :typing_users, updated)}
    end
  end

  def handle_user_stopped_typing(socket, %{user_id: user_id}) do
    typing_users = socket.assigns[:typing_users] || %{}
    updated = Map.delete(typing_users, user_id)
    {:noreply, assign(socket, :typing_users, updated)}
  end

  # --- Presence ---

  def handle_presence_diff(socket, %{joins: joins, leaves: leaves}) do
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
    # Note: presence metadata uses user_id and user_name, not id and username
    updated_viewers =
      current_viewers
      |> Enum.reject(fn user -> MapSet.member?(left_user_ids, "user-#{user.user_id}") end)
      |> Kernel.++(new_users)
      |> Enum.uniq_by(& &1.user_id)
      |> Enum.sort_by(& &1.user_name)

    {:noreply, assign(socket, :viewers, updated_viewers)}
  end

  @doc """
  Handle global presence changes - updates online_friend_ids for breathing avatars.
  """
  def handle_global_presence_diff(socket, %{joins: joins, leaves: leaves}) do
    current_online = socket.assigns[:online_friend_ids] || MapSet.new()
    friends = socket.assigns[:friends] || []
    friend_ids = MapSet.new(Enum.map(friends, & &1.user.id))

    # Extract user IDs from joins (format: "user-123")
    joined_ids =
      joins
      |> Enum.flat_map(fn {key, _} ->
        case key do
          "user-" <> id_str ->
            case Integer.parse(id_str) do
              {id, ""} -> [id]
              _ -> []
            end
          _ -> []
        end
      end)
      |> MapSet.new()
      |> MapSet.intersection(friend_ids)

    # Extract user IDs from leaves
    left_ids =
      leaves
      |> Enum.flat_map(fn {key, _} ->
        case key do
          "user-" <> id_str ->
            case Integer.parse(id_str) do
              {id, ""} -> [id]
              _ -> []
            end
          _ -> []
        end
      end)
      |> MapSet.new()

    # Update online friend IDs
    updated_online =
      current_online
      |> MapSet.union(joined_ids)
      |> MapSet.difference(left_ids)

    {:noreply, assign(socket, :online_friend_ids, updated_online)}
  end

  # --- Public Feed ---

  def handle_new_public_photo(socket, photo) do
    # Ignore if this photo was just uploaded by this socket (to avoid duplication with gallery view)
    ignored_ids = socket.assigns[:uploaded_ids_to_ignore] || MapSet.new()

    if MapSet.member?(ignored_ids, photo.id) do
       {:noreply, socket}
    else
      item = %{
        id: photo.id,
        unique_id: "photo-#{photo.id}",
        type: :photo,
        user_id: photo.user_id,
        user_color: photo.user_color,
        user_name: photo.user_name,
        image_data: photo.image_data,
        thumbnail_data: photo.thumbnail_data,
        content_type: photo.content_type,
        file_size: photo.file_size,
        description: photo.description,
        inserted_at: photo.uploaded_at
      }

      {:noreply,
       socket
       |> assign(:photo_order, merge_photo_order(socket.assigns[:photo_order], [photo.id], :front))
       |> stream_insert(:feed_items, item, at: 0)
       |> assign(:feed_item_count, (socket.assigns[:feed_item_count] || 0) + 1)
       |> then(fn s ->
         if s.assigns[:show_welcome_graph],
           do: push_event(s, "welcome_signal", %{user_id: photo.user_id}),
           else: s
       end)}
    end
  end

  def handle_new_public_note(socket, note) do
    item = %{
      id: note.id,
      unique_id: "note-#{note.id}",
      type: :note,
      user_id: note.user_id,
      user_color: note.user_color,
      user_name: note.user_name,
      content: note.content,
      inserted_at: note.inserted_at
    }

    {:noreply,
     socket
     |> stream_insert(:feed_items, item, at: 0)
     |> assign(:feed_item_count, (socket.assigns[:feed_item_count] || 0) + 1)
     |> then(fn s ->
       if s.assigns[:show_welcome_graph],
         do: push_event(s, "welcome_signal", %{user_id: note.user_id}),
         else: s
     end)}
  end

  # --- Social/Network Events ---
  # These handlers enable real-time updates when connections change

  @doc """
  Handle when someone sends you a connection request.
  Refreshes the pending friend requests list.
  """
  def handle_connection_request_received(socket, _from_user_id) do
    current_user = socket.assigns[:current_user]
    if current_user do
      pending = Social.list_friend_requests(current_user.id)
      {:noreply, assign(socket, :pending_requests, pending)}
    else
      {:noreply, socket}
    end
  end

  @doc """
  Handle when someone accepts your connection request.
  Refreshes the friends list and outgoing requests.
  """
  def handle_connection_accepted(socket, by_user_id) do
    current_user = socket.assigns[:current_user]
    if current_user do
      friends = Social.list_friends(current_user.id)
      pending = Social.list_friend_requests(current_user.id)
      outgoing = Social.list_sent_friend_requests(current_user.id)
      
      {:noreply,
       socket
       |> assign(:friends, friends)
       |> assign(:pending_requests, pending)
       |> assign(:outgoing_friend_requests, outgoing)
       |> push_event("welcome_new_connection", %{from_id: current_user.id, to_id: by_user_id})}
    else
      {:noreply, socket}
    end
  end

  @doc """
  Handle when a connection is removed (friendship deleted).
  Refreshes friends and pending/outgoing requests.
  """
  def handle_friend_removed(socket, _friendship) do
    current_user = socket.assigns[:current_user]
    if current_user do
      friends = Social.list_friends(current_user.id)
      pending = Social.list_friend_requests(current_user.id)
      outgoing = Social.list_sent_friend_requests(current_user.id)
      
      {:noreply,
       socket
       |> assign(:friends, friends)
       |> assign(:pending_requests, pending)
       |> assign(:outgoing_friend_requests, outgoing)}
    else
      {:noreply, socket}
    end
  end

  @doc """
  Handle when someone sends you a trust/recovery request.
  Refreshes the incoming trust requests list.
  """
  def handle_trust_request_received(socket, _from_user_id) do
    current_user = socket.assigns[:current_user]
    if current_user do
      incoming = Social.list_pending_trust_requests(current_user.id)
      {:noreply, assign(socket, :incoming_trust_requests, incoming)}
    else
      {:noreply, socket}
    end
  end

  @doc """
  Handle when someone confirms your trust request.
  Refreshes the trusted friends list.
  """
  def handle_trust_confirmed(socket, _by_user_id) do
    current_user = socket.assigns[:current_user]
    if current_user do
      trusted = Social.list_trusted_friends(current_user.id)
      trusted_ids = Enum.map(trusted, & &1.trusted_user_id)
      outgoing = Social.list_sent_trust_requests(current_user.id)
      {:noreply,
       socket
       |> assign(:trusted_friends, trusted)
       |> assign(:trusted_friend_ids, trusted_ids)
       |> assign(:outgoing_trust_requests, outgoing)}
    else
      {:noreply, socket}
    end
  end

  @doc """
  Handle when user is invited to a group.
  Refreshes the groups list and shows a subtle notification.
  """
  def handle_group_invite_received(socket, invite_info) do
    current_user = socket.assigns[:current_user]
    if current_user do
      # Refresh the user's private rooms list
      private_rooms = Social.list_user_rooms(current_user.id)
      
      # Create notification info for subtle display
      notification = %{
        type: :group_invite,
        room_name: invite_info.room_name || "New Group",
        room_code: invite_info.room_code,
        inviter: invite_info.inviter_username,
        timestamp: DateTime.utc_now()
      }
      
      {:noreply,
       socket
       |> assign(:user_private_rooms, private_rooms)
       |> assign(:group_notification, notification)
       |> put_flash(:info, "You've been invited to #{invite_info.room_name || "a group"} by @#{invite_info.inviter_username}")}
    else
      {:noreply, socket}
    end
  end

  @doc """
  Handle when a new message notification is received via the user's personal channel.
  Shows a flash message if the user is not currently looking at the chat.
  """
  def handle_new_message_notification(socket, %{message: message} = data) do
    # Check if we should alert.
    # We alert if:
    # 1. It's a room message and we are NOT in that room, OR we ARE in the room but chat is closed.
    # 2. It's a conversation message and we are NOT in that conversation.

    is_current_room = socket.assigns[:room] && (
      (data[:room_id] && socket.assigns.room.id == data.room_id) ||
      (message.room_id && socket.assigns.room.id == message.room_id)
    )

    should_alert = cond do
      is_current_room ->
        # If we are in the room, only alert if chat isn't visible
        not (socket.assigns[:show_chat_panel] || socket.assigns[:room_tab] == "chat")

      data[:conversation_id] ->
        # For new-style conversations, check if it's the active one
        socket.assigns[:active_conversation_id] != data.conversation_id

      true ->
        true
    end

    if should_alert do
      sender = message.sender
      username = if sender, do: "@#{sender.username}", else: "Someone"
      
      # Determine context name
      context_name = cond do
        data[:room_name] -> "in #{data.room_name}"
        true -> ""
      end

      # Create notification object
      notification = %{
        id: "msg-#{message.id}",
        sender_username: username,
        room_id: data[:room_id] || message.room_id,
        room_name: data[:room_name] || "Chat",
        text: message.encrypted_content, # In a real app we'd decrypt this or show generic text
        timestamp: DateTime.utc_now()
      }

      {:noreply, assign(socket, :persistent_notification, notification)}
    else
      {:noreply, socket}
    end
  end
end

