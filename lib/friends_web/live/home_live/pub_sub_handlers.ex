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

  # --- Chat ---

  def handle_new_room_message(socket, message) do
    if socket.assigns.show_chat_panel or socket.assigns.room_tab == "chat" do
      messages = socket.assigns.room_messages ++ [message]
      {:noreply, assign(socket, :room_messages, messages)}
    else
      {:noreply, socket}
    end
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
    updated_viewers =
      current_viewers
      |> Enum.reject(fn user -> MapSet.member?(left_user_ids, "user-#{user.id}") end)
      |> Kernel.++(new_users)
      |> Enum.uniq_by(& &1.id)
      |> Enum.sort_by(& &1.username)

    {:noreply, assign(socket, :viewers, updated_viewers)}
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
end
