defmodule FriendsWeb.HomeLive.Events.PhotoEvents do
  @moduledoc """
  Event handlers for Photo interactions (Upload, View, Delete, Navigation).
  """
  import Phoenix.Component
  import Phoenix.LiveView
  import FriendsWeb.HomeLive.Helpers
  alias Friends.Social
  alias Friends.Repo
  import Ecto.Query

  # --- Upload Handlers ---

  def validate(socket), do: {:noreply, socket}
  def save(socket), do: {:noreply, socket}
  def validate_feed_photo(socket), do: {:noreply, socket}

  def cancel_upload(socket, ref) do
    {:noreply, socket |> cancel_upload(:photo, ref) |> assign(:uploading, false)}
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

  def handle_progress(:photo, _entry, socket) do
    {:noreply, assign(socket, :uploading, true)}
  end

  def handle_progress(:feed_photo, entry, socket) when entry.done? do
    # Only registered users can post to public feed
    if is_nil(socket.assigns.current_user) do
      {:noreply, put_flash(socket, :error, "Please login to post photos")}
    else
      user = socket.assigns.current_user

      [photo_result] =
        consume_uploaded_entries(socket, :feed_photo, fn %{path: path}, _entry ->
          binary = File.read!(path)

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

      case photo_result do
        %{error: :invalid_image} ->
          {:noreply,
           socket
           |> assign(:uploading, false)
           |> put_flash(
             :error,
             "Invalid file type. Please upload a valid image (JPEG, PNG, GIF, or WebP)."
           )}

        %{data_url: data_url, content_type: content_type, file_size: file_size} ->
          attrs = %{
            user_id: "user-#{user.id}",
            user_color: socket.assigns.user_color,
            user_name: user.display_name || user.username,
            image_data: data_url,
            content_type: content_type,
            file_size: file_size
          }

          result = Social.create_public_photo(attrs, user.id)

          case result do
            {:ok, photo} ->
              photo_item = %{
                id: photo.id,
                type: "photo",
                user_id: photo.user_id,
                user_color: photo.user_color,
                user_name: photo.user_name,
                thumbnail_data: photo.thumbnail_data,
                image_data: photo.image_data,
                content_type: photo.content_type,
                file_size: photo.file_size,
                description: photo.description,
                inserted_at: photo.uploaded_at
              }

              {:noreply,
               socket
               |> assign(:uploading, false)
               |> assign(:feed_item_count, socket.assigns.feed_item_count + 1)
               |> stream_insert(:feed_items, photo_item, at: 0)
               |> push_event("photo_uploaded", %{photo_id: photo.id})}

            {:error, _} ->
              {:noreply,
               socket |> assign(:uploading, false) |> put_flash(:error, "Upload failed")}
          end
      end
    end
  end

  def handle_progress(_, _, socket), do: {:noreply, socket}

  # --- Viewing & Management ---

  def delete_photo(socket, id) do
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
                   |> assign(
                     :photo_order,
                     remove_photo_from_order(socket.assigns.photo_order, photo_id)
                   )
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

  def view_feed_photo(socket, photo_id) do
    # Use helper which handles getting photo and assigning it
    {:noreply, load_photo_into_modal(socket, photo_id)}
  end

  def close_photo_modal(socket) do
    {:noreply, assign(socket, :viewing_photo, nil)}
  end

  def view_full_image(socket, photo_id) do
    {:noreply, load_photo_into_modal(socket, photo_id)}
  end

  def close_image_modal(socket) do
    {:noreply,
     socket
     |> assign(:show_image_modal, false)
     |> assign(:full_image_data, nil)
     |> assign(:current_photo_id, nil)}
  end

  def next_photo(socket), do: {:noreply, navigate_photo(socket, :next)}
  def prev_photo(socket), do: {:noreply, navigate_photo(socket, :prev)}

  def set_thumbnail(socket, photo_id, thumbnail_data) do
    # Pass current user ID for authorization
    user_id = socket.assigns.user_id

    case Social.update_photo_thumbnail(photo_id, thumbnail_data, user_id) do
      {:ok, photo} ->
        # Update the stream item with the new thumbnail
        photo_with_type =
          photo
          |> Map.from_struct()
          |> Map.put(:type, :photo)
          |> Map.put(:unique_id, "photo-#{photo.id}")
          
        # Determine which stream to update based on where the photo is
        socket = 
          if socket.assigns[:feed_item_count] do
            stream_insert(socket, :feed_items, photo_with_type)
          else
            stream_insert(socket, :items, photo_with_type)
          end

        {:noreply, socket}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def regenerate_thumbnails(socket) do
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

  # --- Private Helpers ---

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
  def regenerate_all_missing_thumbnails(room_id, room_code) do
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
end
