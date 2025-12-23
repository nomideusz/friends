defmodule FriendsWeb.HomeLive.Events.NoteEvents do
  @moduledoc """
  Event handlers for Notes (text and voice).
  """
  import Phoenix.Component
  import Phoenix.LiveView
  import FriendsWeb.HomeLive.Helpers
  alias Friends.Social

  # --- Note Modal ---

  def open_note_modal(socket) do
    # Only registered users can open note modal
    if socket.assigns.current_user && not socket.assigns.room_access_denied do
      action = if socket.assigns[:room], do: "save_note", else: "post_feed_note"
      {:noreply,
       socket
       |> assign(:show_create_menu, false)
       |> assign(:show_note_modal, true)
       |> assign(:note_input, "")
       |> assign(:note_modal_action, action)}
    else
      {:noreply, socket}
    end
  end

  def close_note_modal(socket) do
    {:noreply, socket |> assign(:show_note_modal, false) |> assign(:note_input, "")}
  end

  def update_note(socket, content) do
    {:noreply, assign(socket, :note_input, content)}
  end

  def save_note(socket, content) do
    content = String.trim(content)
    content_length = String.length(content)
    
    cond do
      content == "" -> 
        {:noreply, socket}
        
      content_length > 500 ->
        {:noreply, put_flash(socket, :error, "Note is too long (max 500 characters)")}
        
      socket.assigns.current_user && not socket.assigns.room_access_denied ->
        case Social.create_note(
             %{
               user_id: socket.assigns.user_id,
               user_color: socket.assigns.user_color,
               user_name: socket.assigns.user_name,
               content: content,
               room_id: socket.assigns.room.id
             },
             socket.assigns.room.code
           ) do
        {:ok, note} ->
          note_with_type = note |> Map.put(:type, :note) |> Map.put(:unique_id, "note-#{note.id}")

          {:noreply,
           socket
           |> assign(:show_note_modal, false)
           |> assign(:note_input, "")
           |> assign(:item_count, socket.assigns.item_count + 1)
           |> stream_insert(:items, note_with_type, at: 0)
           |> put_flash(:info, "Note added!")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "failed")}
      end
      
      true ->
        {:noreply, socket}
    end
  end

  def delete_note(socket, id) do
    case safe_to_integer(id) do
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "invalid id")}

      {:ok, note_id} ->
        room_code = if socket.assigns[:room], do: socket.assigns.room.code, else: nil
        is_admin = Social.is_admin?(socket.assigns.current_user)

        # Use admin delete if admin, otherwise regular delete
        result = if is_admin do
          Social.admin_delete_note(note_id, room_code)
        else
          Social.delete_note(note_id, socket.assigns.user_id, room_code)
        end

        case result do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(:item_count, max(0, socket.assigns.item_count - 1))
             |> stream_delete(:items, %{id: note_id, unique_id: "note-#{note_id}"})}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "cannot delete")}
        end
    end
  end

  # --- View Note ---

  def view_full_note(socket, params) do
    id = params["id"]
    content = params["content"]
    user = params["user"]
    time = params["time"]

    {:noreply, assign(socket, :viewing_note, %{id: id, content: content, user: user, time: time})}
  end

  def close_view_note(socket) do
    {:noreply, assign(socket, :viewing_note, nil)}
  end

  def view_feed_note(socket, note_id) do
    note_id = if is_binary(note_id), do: String.to_integer(note_id), else: note_id
    case Friends.Social.Notes.get_note(note_id) do
      nil -> 
        {:noreply, socket}
      note ->
        viewing_note = %{
          id: note.id,
          content: note.content,
          user: %{username: note.user_name, id: note.user_id},
          time: format_note_time(note.inserted_at)
        }
        {:noreply, assign(socket, :viewing_note, viewing_note)}
    end
  end

  defp format_note_time(nil), do: "Just now"
  defp format_note_time(datetime) do
    now = NaiveDateTime.utc_now()
    diff = NaiveDateTime.diff(now, datetime, :second)
    cond do
      diff < 60 -> "Just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86400)}d ago"
    end
  end

  # --- Feed Notes (Public) ---

  def open_feed_note_modal(socket) do
    {:noreply,
     socket
     |> assign(:show_create_menu, false)
     |> assign(:show_note_modal, true)
     |> assign(:note_input, "")
     |> assign(:note_modal_action, "post_feed_note")}
  end

  def post_feed_note(socket, content) do
    require Logger
    Logger.debug("post_feed_note called with content: #{inspect(content)}")
    
    content_length = String.length(content)
    user = socket.assigns.current_user
    Logger.debug("post_feed_note user: #{inspect(user && user.id)}")

    cond do
      user == nil or String.trim(content) == "" ->
        Logger.debug("post_feed_note skipped - user nil or empty content")
        {:noreply, socket}
        
      content_length > 500 ->
        {:noreply, put_flash(socket, :error, "Note is too long (max 500 characters)")}

      true ->
        attrs = %{
          content: content,
          user_id: "user-#{user.id}",
          user_color: socket.assigns.user_color,
          user_name: user.display_name || user.username
        }

        Logger.debug("post_feed_note creating note with attrs: #{inspect(attrs)}")

        case Social.create_public_note(attrs, user.id) do
        {:ok, note} ->
          Logger.info("post_feed_note SUCCESS - note created: #{inspect(note.id)}")
          
          note_with_type =
            note
            |> Map.put(:type, :note)
            |> Map.put(:unique_id, "note-#{note.id}")

          {:noreply,
           socket
           |> assign(:show_note_modal, false)
           |> assign(:note_input, "")
           |> assign(:feed_item_count, (socket.assigns[:feed_item_count] || 0) + 1)
           |> stream_insert(:feed_items, note_with_type, at: 0)}

        {:error, reason} ->
          Logger.error("post_feed_note FAILED: #{inspect(reason)}")
          {:noreply, put_flash(socket, :error, "Failed to post note")}
      end
    end
  end

  def start_voice_recording(socket) do
    {:noreply,
     socket
     |> assign(:show_create_menu, false)
     |> assign(:recording_voice, true)
     |> push_event("start_js_recording", %{})}
  end

  def cancel_voice_recording(socket) do
    {:noreply, assign(socket, :recording_voice, false)}
  end

  def post_public_voice(socket, %{"audio_data" => audio_data} = params) do
    user = socket.assigns.current_user
    duration_ms = params["duration_ms"] || 0

    if user && audio_data && audio_data != "" do
      # Decode base64 audio data
      decoded_audio = Base.decode64!(audio_data)
      filename = "public/#{user.id}/voice-#{Ecto.UUID.generate()}.webm"

      # Upload to S3 first
      case Friends.Storage.upload_file(decoded_audio, filename, "audio/webm") do
        {:ok, url} ->
          attrs = %{
            user_id: "user-#{user.id}",
            user_color: socket.assigns.user_color,
            user_name: user.display_name || user.username,
            image_data: url,
            thumbnail_data: nil,
            content_type: "audio/webm",
            description: "#{duration_ms}",
            file_size: byte_size(decoded_audio)
          }

          case Social.create_public_photo(attrs, user.id) do
            {:ok, photo} ->
              item =
                photo
                |> Map.from_struct()
                |> Map.put(:type, :photo)
                |> Map.put(:unique_id, "photo-#{photo.id}")

              {:noreply,
               socket
               |> assign(:recording_voice, false)
               |> assign(:feed_item_count, (socket.assigns[:feed_item_count] || 0) + 1)
               |> stream_insert(:feed_items, item, at: 0)}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Failed to post voice message")}
          end

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Failed to upload voice message")}
      end
    else
      {:noreply, assign(socket, :recording_voice, false)}
    end
  end

  # --- Voice Notes (Grid) ---

  def save_grid_voice_note(socket, %{
        "encrypted_content" => encrypted,
        "nonce" => nonce,
        "duration_ms" => duration
      }) do
    if socket.assigns.current_user && not socket.assigns.room_access_denied do
      message_params = %{
        user_id: socket.assigns.user_id,
        user_color: socket.assigns.user_color,
        user_name: socket.assigns.user_name,
        room_id: socket.assigns.room.id,
        content_type: "audio/encrypted",
        image_data: encrypted,
        thumbnail_data: nonce,
        description: "#{duration}",
        file_size: 0
      }

      case Social.create_photo(message_params, socket.assigns.room.code) do
        {:ok, photo} ->
          item =
            photo
            |> Map.from_struct()
            |> Map.put(:type, :photo)
            |> Map.put(:unique_id, "photo-#{photo.id}")

          {:noreply,
           socket
           |> assign(:item_count, socket.assigns.item_count + 1)
           |> stream_insert(:items, item, at: 0)
           |> assign(:recording_voice, false)
           |> put_flash(:info, "Voice note sent!")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to save voice note")}
      end
    else
      {:noreply, socket}
    end
  end
end
