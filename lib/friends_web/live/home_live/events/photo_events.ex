defmodule FriendsWeb.HomeLive.Events.PhotoEvents do
  @moduledoc """
  Event handlers for Photo interactions (Upload, View, Delete, Navigation).
  """
  import Phoenix.Component
  import Phoenix.LiveView
  import FriendsWeb.HomeLive.Helpers
  alias Friends.Social

  # --- Upload Handlers ---

  def validate(socket), do: {:noreply, socket}
  def save(socket), do: {:noreply, socket}
  def validate_feed_photo(socket), do: {:noreply, socket}

  def cancel_upload(socket, ref) do
    {:noreply, socket |> cancel_upload(:photo, ref) |> assign(:uploading, false)}
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
end
