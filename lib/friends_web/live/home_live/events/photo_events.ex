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
    if is_nil(socket.assigns.current_user) or socket.assigns.room_access_denied do
      {:noreply, put_flash(socket, :error, "Please register to upload photos")}
    else
      results =
        consume_uploaded_entries(socket, :photo, fn %{path: path}, entry ->
          file_content = File.read!(path)
          filename = "#{socket.assigns.current_user.id}/#{Ecto.UUID.generate()}-#{entry.client_name}"

          # Process image to generate variants
          with {:ok, variants} <- Friends.ImageProcessor.process_upload(file_content, entry.client_type),
               {:ok, urls} <- Friends.Storage.upload_with_variants(variants, filename, entry.client_type) do
            case Social.create_photo(
                   %{
                     user_id: socket.assigns.user_id,
                     user_name: socket.assigns.current_user.username,
                     user_color: socket.assigns.user_color,
                     image_data: urls.original_url,
                     thumbnail_data: urls[:thumb_url] || urls.original_url,
                     image_url_thumb: urls[:thumb_url],
                     image_url_medium: urls[:medium_url],
                     image_url_large: urls[:large_url],
                     content_type: entry.client_type,
                     file_size: entry.client_size,
                     description: "",
                     room_id: socket.assigns.room.id
                   },
                   socket.assigns.room.code
                 ) do
              {:ok, photo} -> {:ok, photo}
              {:error, reason} -> {:postpone, reason}
            end
          else
            {:error, reason} ->
              require Logger
              Logger.error("Room photo upload failed: #{inspect(reason)}")
              {:postpone, :upload_failed}
          end
        end)

      case List.first(results) do
        {:ok, photo} ->
          photo_with_type =
            photo
            |> Map.put(:type, :photo)
            |> Map.put(:unique_id, "photo-#{photo.id}")

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

        _ ->
          {:noreply,
           socket |> assign(:uploading, false) |> put_flash(:error, "Upload failed")}
      end
    end
  end

  def handle_progress(:photo, _entry, socket) do
    {:noreply, assign(socket, :uploading, true)}
  end

  def handle_progress(:feed_photo, entry, socket) when entry.done? do
    if is_nil(socket.assigns.current_user) do
      {:noreply, put_flash(socket, :error, "Please login to post photos")}
    else
      results =
        consume_uploaded_entries(socket, :feed_photo, fn %{path: path}, entry ->
          file_content = File.read!(path)
          filename = "public/#{socket.assigns.current_user.id}/#{Ecto.UUID.generate()}-#{entry.client_name}"

          # Process image to generate variants
          with {:ok, variants} <- Friends.ImageProcessor.process_upload(file_content, entry.client_type),
               {:ok, urls} <- Friends.Storage.upload_with_variants(variants, filename, entry.client_type) do
            case Social.create_public_photo(
                   %{
                     user_id: socket.assigns.user_id,
                     user_name: socket.assigns.current_user.username,
                     user_color: socket.assigns.user_color,
                     image_data: urls.original_url,
                     thumbnail_data: urls[:thumb_url] || urls.original_url,
                     image_url_thumb: urls[:thumb_url],
                     image_url_medium: urls[:medium_url],
                     image_url_large: urls[:large_url],
                     content_type: entry.client_type,
                     file_size: entry.client_size,
                     description: ""
                   },
                   socket.assigns.current_user.id
                 ) do
              {:ok, photo} -> {:ok, photo}
              {:error, reason} ->
                require Logger
                Logger.error("Feed photo DB insert failed: #{inspect(reason)}")
                {:postpone, reason}
            end
          else
            {:error, reason} ->
              require Logger
              Logger.error("Feed photo upload failed: #{inspect(reason)}")
              {:postpone, :upload_failed}
          end
        end)

      case List.first(results) do
        {:ok, photo} ->
          photo_with_type =
            photo
            |> Map.put(:type, :photo)
            |> Map.put(:unique_id, "photo-#{photo.id}")

          {:noreply,
           socket
           |> assign(:uploading, false)
           |> assign(:feed_item_count, (socket.assigns[:feed_item_count] || 0) + 1)
           |> stream_insert(:feed_items, photo_with_type, at: 0)
           |> push_event("photo_uploaded", %{photo_id: photo.id})}

        _ ->
          {:noreply,
           socket |> assign(:uploading, false) |> put_flash(:error, "Upload failed")}
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
