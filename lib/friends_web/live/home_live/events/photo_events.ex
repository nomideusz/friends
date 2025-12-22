defmodule FriendsWeb.HomeLive.Events.PhotoEvents do
  @moduledoc """
  Event handlers for Photo interactions (Upload, View, Delete, Navigation).
  """
  import Phoenix.Component
  import Phoenix.LiveView
  import FriendsWeb.HomeLive.Helpers
  alias Friends.Social
  alias Friends.Repo
  require Logger
  import Ecto.Query

  # --- Upload Handlers ---

  def validate(socket), do: {:noreply, socket}
  def save(socket), do: {:noreply, socket}
  def validate_feed_photo(socket), do: {:noreply, socket}
  def save_feed_photo(socket), do: {:noreply, socket}

  def cancel_upload(socket, ref) do
    {:noreply, socket |> cancel_upload(:photo, ref) |> assign(:uploading, false)}
  end

  def handle_progress(:photo, _entry, socket) do
    if Enum.all?(socket.assigns.uploads.photo.entries, & &1.done?) do
      if is_nil(socket.assigns.current_user) or socket.assigns.room_access_denied do
        {:noreply, put_flash(socket, :error, "Please register to upload photos")}
      else
        # Generate batch_id for this upload session (multiple photos)
        batch_id = if length(socket.assigns.uploads.photo.entries) > 1 do
          Ecto.UUID.generate()
        else
          nil  # Single photos don't get batch_id
        end

        results =
          consume_uploaded_entries(socket, :photo, fn %{path: path}, entry ->
            Logger.info("PhotoEvents: Processing private photo entry #{entry.ref}")
            process_photo_entry(socket, path, entry, :room, batch_id)
          end)

        # Process successful uploads
        {socket, uploaded_photos} =
          Enum.reduce(results, {socket, []}, fn
            {photo, temp_path, client_type}, {acc_socket, acc_photos} when is_struct(photo, Friends.Social.Photo) ->
              # 1. Start background task
              start_background_processing(photo, temp_path, client_type, acc_socket.assigns.user_id)
              
              # 2. Notify client
              acc_socket = push_event(acc_socket, "photo_uploaded", %{photo_id: photo.id})
              
              {acc_socket, [photo | acc_photos]}

            _, acc -> acc
          end)

        uploaded_photos = Enum.reverse(uploaded_photos)
        
        # Group by batch_id to form galleries
        {batched, singles} = Enum.split_with(uploaded_photos, & &1.batch_id)
        
        gallery_items =
          batched
          |> Enum.group_by(& &1.batch_id)
          |> Enum.map(fn {batch_id, photos} ->
            first = List.first(photos)
            %{
              type: :gallery,
              batch_id: batch_id,
              photo_count: length(photos),
              first_photo: Map.from_struct(first),
              all_photos: Enum.map(photos, &Map.from_struct/1),
              user_id: first.user_id,
              user_name: first.user_name,
              user_color: first.user_color,
              uploaded_at: first.uploaded_at,
              id: "gallery-#{batch_id}",
              unique_id: "gallery-#{batch_id}"
            }
          end)
          
        single_items =
          Enum.map(singles, fn photo ->
            photo
            |> Map.from_struct()
            |> Map.put(:type, :photo)
            |> Map.put(:unique_id, "photo-#{photo.id}")
          end)
          
        # Stream items (galleries + singles)
        socket =
          (gallery_items ++ single_items)
          |> Enum.reduce(socket, fn item, acc ->
            acc
            |> assign(:item_count, (acc.assigns[:item_count] || 0) + 1)
            |> stream_insert(:items, item, at: 0)
          end)
          
        # Update navigation order with ALL individual photo IDs
        all_new_ids = Enum.map(uploaded_photos, & &1.id)
        socket = assign(socket, :photo_order, merge_photo_order(socket.assigns[:photo_order], all_new_ids, :front))
        
        # Add to ignore list to prevent PubSub duplication (since we manually inserted gallery/singles)
        ignored_ids = MapSet.union(socket.assigns[:uploaded_ids_to_ignore] || MapSet.new(), MapSet.new(all_new_ids))
        socket = assign(socket, :uploaded_ids_to_ignore, ignored_ids)

        failed_count = Enum.count(results, fn res -> match?({:postpone, _}, res) end)

        socket = 
          if failed_count > 0 do
            put_flash(socket, :error, "#{failed_count} uploads failed")
          else
            socket
          end
        
        {:noreply, assign(socket, :uploading, false)}
      end
    else
      {:noreply, assign(socket, :uploading, true)}
    end
  end



  def handle_progress(:feed_photo, _entry, socket) do
    if Enum.all?(socket.assigns.uploads.feed_photo.entries, & &1.done?) do
      if is_nil(socket.assigns.current_user) do
        {:noreply, put_flash(socket, :error, "Please login to post photos")}
      else
        # Generate batch_id for this upload session (multiple photos)
        batch_id = if length(socket.assigns.uploads.feed_photo.entries) > 1 do
          Ecto.UUID.generate()
        else
          nil  # Single photos don't get batch_id
        end

        results =
          consume_uploaded_entries(socket, :feed_photo, fn %{path: path}, entry ->
            process_photo_entry(socket, path, entry, :feed, batch_id)
          end)

        # Process successful uploads
        # Process successful uploads
        {socket, uploaded_photos} =
          Enum.reduce(results, {socket, []}, fn
            {photo, temp_path, client_type}, {acc_socket, acc_photos} when is_struct(photo, Friends.Social.Photo) ->
              # Start background task for full processing
              start_background_processing(photo, temp_path, client_type, photo.user_id)
              
              # Notify client
              acc_socket = push_event(acc_socket, "photo_uploaded", %{photo_id: photo.id})
              
              {acc_socket, [photo | acc_photos]}

            _, acc -> acc
          end)
        
        uploaded_photos = Enum.reverse(uploaded_photos)
        
        # Group by batch_id to form galleries
        {batched, singles} = Enum.split_with(uploaded_photos, & &1.batch_id)
        
        gallery_items =
          batched
          |> Enum.group_by(& &1.batch_id)
          |> Enum.map(fn {batch_id, photos} ->
            first = List.first(photos)
            %{
              type: :gallery,
              batch_id: batch_id,
              photo_count: length(photos),
              first_photo: Map.from_struct(first),
              all_photos: Enum.map(photos, &Map.from_struct/1),
              user_id: first.user_id,
              user_name: first.user_name,
              user_color: first.user_color,
              uploaded_at: first.uploaded_at,
              id: "gallery-#{batch_id}",
              unique_id: "gallery-#{batch_id}"
            }
          end)
          
        single_items =
          Enum.map(singles, fn photo ->
            photo
            |> Map.from_struct()
            |> Map.put(:type, :photo)
            |> Map.put(:unique_id, "photo-#{photo.id}")
          end)
          
        # Stream items (galleries + singles)
        socket =
          (gallery_items ++ single_items)
          |> Enum.reduce(socket, fn item, acc ->
            acc
            |> assign(:feed_item_count, (acc.assigns[:feed_item_count] || 0) + 1)
            |> stream_insert(:feed_items, item, at: 0)
          end)
          
        # Update navigation order with ALL individual photo IDs
        all_new_ids = Enum.map(uploaded_photos, & &1.id)
        socket = assign(socket, :photo_order, merge_photo_order(socket.assigns[:photo_order], all_new_ids, :front))
        
        # Add to ignore list to prevent PubSub duplication (since we manually inserted gallery/singles)
        ignored_ids = MapSet.union(socket.assigns[:uploaded_ids_to_ignore] || MapSet.new(), MapSet.new(all_new_ids))
        socket = assign(socket, :uploaded_ids_to_ignore, ignored_ids)
        
        # Cleanup and flash for errors
        failed_count = Enum.count(results, fn res -> match?({:postpone, _}, res) end)

        socket = 
          if failed_count > 0 do
            put_flash(socket, :error, "#{failed_count} uploads failed")
          else
            socket
          end
          
        # Hide constellation - user wants to see their feed now
        # Keep constellation visible
        socket = socket
          
        {:noreply, assign(socket, :uploading, false)}
      end
    else
      {:noreply, assign(socket, :uploading, true)}
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
            # Allow deletion if owner OR admin
            is_owner = photo.user_id == socket.assigns.user_id
            is_admin = Social.is_admin?(socket.assigns.current_user)

            if is_owner or is_admin do
              room_code = if socket.assigns[:room], do: socket.assigns.room.code, else: nil
              case Social.delete_photo(photo_id, room_code) do
                {:ok, _} ->
                  # Update UI based on context (Feed vs Room)
                  socket =
                    if socket.assigns[:feed_item_count] do
                      socket
                      |> assign(:feed_item_count, max(0, socket.assigns.feed_item_count - 1))
                      |> stream_delete(:feed_items, %{id: photo_id, unique_id: "photo-#{photo_id}", type: :photo})
                    else
                      socket
                      |> assign(:item_count, max(0, (socket.assigns[:item_count] || 0) - 1))
                      |> stream_delete(:items, %{id: photo_id, unique_id: "photo-#{photo_id}"})
                    end

                  {:noreply,
                   socket
                   |> maybe_close_deleted_photo(photo_id)
                   |> assign(
                     :photo_order,
                     remove_photo_from_order(socket.assigns[:photo_order], photo_id)
                   )}

                {:error, _} ->
                  {:noreply, put_flash(socket, :error, "failed")}
              end
            else
              {:noreply, put_flash(socket, :error, "not yours")}
            end
        end
    end
  end

  @doc """
  Deletes an entire gallery (batch) of photos. Admin only.
  """
  def delete_gallery(socket, batch_id) do
    current_user = socket.assigns.current_user

    if Social.is_admin?(current_user) do
      case Social.delete_gallery(batch_id) do
        {:ok, count} ->
          # Remove gallery from stream
          socket =
            if socket.assigns[:feed_item_count] do
              socket
              |> assign(:feed_item_count, max(0, socket.assigns.feed_item_count - 1))
              |> stream_delete(:feed_items, %{id: "gallery-#{batch_id}", unique_id: "gallery-#{batch_id}", type: :gallery})
            else
              socket
              |> assign(:item_count, max(0, (socket.assigns[:item_count] || 0) - 1))
              |> stream_delete(:items, %{id: "gallery-#{batch_id}", unique_id: "gallery-#{batch_id}"})
            end

          {:noreply, put_flash(socket, :info, "Deleted #{count} photos")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Delete failed")}
      end
    else
      {:noreply, put_flash(socket, :error, "Admin only")}
    end
  end

  def view_gallery(socket, batch_id) do
    # 1. Fetch all photos in this batch
    photos = Social.list_batch_photos(batch_id)
    
    case photos do
      [first | _] = batch_photos ->
        # 2. Update photo_order to JUST this gallery (so prev/next works within gallery)
        gallery_photo_ids = Enum.map(batch_photos, & &1.id)
        
        # 3. Open modal with the first photo
        new_socket = 
          socket
          |> assign(:photo_order, gallery_photo_ids)
          |> load_photo_into_modal(first.id)
          
        {:noreply, new_socket}
        
      [] ->
        {:noreply, put_flash(socket, :error, "Gallery not found")}
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
    # Broadcast that we're viewing this photo (shared attention)
    socket = broadcast_viewing_start(socket, photo_id)
    {:noreply, load_photo_into_modal(socket, photo_id)}
  end

  def close_image_modal(socket) do
    # Broadcast that we stopped viewing (if we were viewing a photo)
    socket = if socket.assigns[:current_photo_id] do
      broadcast_viewing_stop(socket, socket.assigns.current_photo_id)
    else
      socket
    end

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

  # --- Private Helpers ---

  # Broadcast when user starts viewing a photo (shared attention)
  defp broadcast_viewing_start(socket, photo_id) do
    room = socket.assigns[:room]
    current_user = socket.assigns[:current_user]

    if room && current_user do
      Phoenix.PubSub.broadcast(
        Friends.PubSub,
        "room:#{room.id}:viewing",
        {:user_viewing, %{
          user_id: current_user.id,
          username: current_user.username,
          photo_id: photo_id,
          timestamp: System.system_time(:millisecond)
        }}
      )
    end

    socket
  end

  # Broadcast when user stops viewing a photo
  defp broadcast_viewing_stop(socket, photo_id) do
    room = socket.assigns[:room]
    current_user = socket.assigns[:current_user]

    if room && current_user do
      Phoenix.PubSub.broadcast(
        Friends.PubSub,
        "room:#{room.id}:viewing",
        {:user_stopped_viewing, %{
          user_id: current_user.id,
          photo_id: photo_id
        }}
      )
    end

    socket
  end

  defp process_photo_entry(socket, path, entry, context, batch_id) do
    try do
      file_content = File.read!(path)
      
      # 1. Generate fast thumbnail
      with {:ok, thumb_binary, thumb_type} <- Friends.ImageProcessor.generate_thumbnail_only(file_content, entry.client_type) do
        # 2. Upload thumbnail only
        uuid = Ecto.UUID.generate()
        base_path = if context == :room, 
          do: "#{socket.assigns.current_user.id}/#{uuid}-#{Path.rootname(entry.client_name)}",
          else: "public/#{socket.assigns.current_user.id}/#{uuid}-#{Path.rootname(entry.client_name)}"
          
        thumb_filename = "#{base_path}_thumb.jpg"
        
        with {:ok, thumb_url} <- Friends.Storage.upload_file(thumb_binary, thumb_filename, thumb_type) do
          # 3. Create DB record with thumbnail and placeholder
          attrs = %{
            user_id: socket.assigns.user_id,
            user_name: socket.assigns.current_user.username,
            user_color: socket.assigns.user_color,
            # Use thumbnail as temporary main image
            image_data: thumb_url,
            thumbnail_data: thumb_url,
            image_url_thumb: thumb_url,
            content_type: entry.client_type,
            file_size: entry.client_size,
            description: "",
            batch_id: batch_id  # Add batch_id for gallery grouping
          }
          
          attrs = if context == :room,
            do: Map.put(attrs, :room_id, socket.assigns.room.id),
            else: attrs
            
          result = if context == :room,
            do: Social.create_photo(attrs, socket.assigns.room.code),
            else: Social.create_public_photo(attrs, socket.assigns.current_user.id)
            
          case result do
            {:ok, photo} -> 
              # Make a temp copy for background processing
              temp_path = Path.join(System.tmp_dir!(), "#{uuid}-#{entry.client_name}")
              File.cp!(path, temp_path)
              
              {:ok, {photo, temp_path, entry.client_type}}
              
            {:error, reason} -> 
               require Logger
               Logger.error("Photo create failed: #{inspect(reason)}")
               {:postpone, reason}
          end
        else
          {:error, reason} ->
            require Logger
            Logger.error("Thumbnail upload failed: #{inspect(reason)}")
            {:postpone, :upload_failed}
        end
      else
        {:error, reason} ->
          require Logger
          Logger.error("Fast thumbnail gen failed: #{inspect(reason)}")
          {:postpone, :upload_failed}
      end
    rescue
      e ->
        require Logger
        Logger.error("Process photo entry crashed: #{inspect(e)}")
        {:postpone, :processing_crashed}
    end
  end

  defp start_background_processing(photo, temp_path, client_type, user_id) do
    Task.start(fn ->
      try do
        file_content = File.read!(temp_path)

        with {:ok, variants, processed} <- Friends.ImageProcessor.process_upload(file_content, client_type) do
           bucket = Application.get_env(:friends, :media_bucket, "friends-images")
           path_segments = 
             photo.image_url_thumb
             |> URI.parse()
             |> Map.get(:path)
             |> String.split("/")
             |> Enum.reject(&(&1 == ""))

           base_virtual_path = 
             case path_segments do
               [^bucket | rest] -> rest
               other -> other
             end
             |> Enum.join("/")
             |> Path.rootname()
             |> String.replace_suffix("_thumb", "")
             |> Path.rootname()
           
           ext = MIME.extensions(client_type) |> List.first() || "bin"
           full_base_filename = "#{base_virtual_path}.#{ext}"
           
           case Friends.Storage.upload_with_variants(variants, full_base_filename, client_type, processed) do
             {:ok, urls} ->
               Logger.info("Background upload success. Updating DB for photo #{photo.id} with user_id #{user_id}")
               case Friends.Social.Photos.update_photo_urls(photo.id, urls, user_id) do
                 {:ok, _} -> Logger.info("DB update success")
                 {:error, reason} -> Logger.error("DB update failed: #{inspect(reason)}")
               end
               
             {:error, reason} ->
               Logger.error("Storage upload failed: #{inspect(reason)}")
           end
        end
        
        File.rm(temp_path)
      rescue
        e -> 
          require Logger
          Logger.error("Background photo processing failed: #{inspect(e)}")
          File.rm(temp_path)
      end
    end)
  end
  
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
