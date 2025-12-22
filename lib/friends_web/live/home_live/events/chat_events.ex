defmodule FriendsWeb.HomeLive.Events.ChatEvents do
  @moduledoc """
  Event handlers for Chat UI interactions.
  Includes live typing feature for real-time presence.
  """
  import Phoenix.Component
  import Phoenix.LiveView

  def toggle_mobile_chat(socket) do
    {:noreply, update(socket, :show_mobile_chat, &(!&1))}
  end

  def toggle_members_panel(socket) do
    {:noreply, update(socket, :show_members_panel, &(!&1))}
  end

  def toggle_chat_expanded(socket) do
    {:noreply, update(socket, :chat_expanded, &(!&1))}
  end

  def toggle_chat_visibility(socket) do
    current = socket.assigns[:show_chat]
    # Default to true if nil, so toggling makes it false
    new_value = if is_nil(current), do: false, else: !current
    {:noreply, assign(socket, :show_chat, new_value)}
  end

  # ============================================================================
  # LIVE TYPING
  # Broadcasts keystrokes to other room members in real-time
  # ============================================================================

  @doc """
  Handle typing event - broadcast to other users
  """
  def handle_typing(socket, text) do
    room = socket.assigns[:room]
    current_user = socket.assigns[:current_user]

    if room && current_user do
      # Broadcast typing to room topic
      Phoenix.PubSub.broadcast(
        Friends.PubSub,
        "room:#{room.id}:typing",
        {:user_typing, %{
          user_id: current_user.id,
          username: current_user.username,
          text: text,
          timestamp: System.system_time(:millisecond)
        }}
      )
    end

    # Also update local state for the input
    {:noreply, assign(socket, :new_chat_message, text)}
  end

  @doc """
  Handle stop typing - clear user's typing indicator
  """
  def handle_stop_typing(socket) do
    room = socket.assigns[:room]
    current_user = socket.assigns[:current_user]

    if room && current_user do
      Phoenix.PubSub.broadcast(
        Friends.PubSub,
        "room:#{room.id}:typing",
        {:user_stopped_typing, %{user_id: current_user.id}}
      )
    end

    {:noreply, socket}
  end

  @doc """
  Handle incoming typing broadcast from another user
  """
  def handle_typing_broadcast(socket, %{user_id: user_id, username: username, text: text}) do
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

  @doc """
  Handle user stopped typing broadcast
  """
  def handle_stopped_typing_broadcast(socket, %{user_id: user_id}) do
    typing_users = socket.assigns[:typing_users] || %{}
    updated = Map.delete(typing_users, user_id)
    {:noreply, assign(socket, :typing_users, updated)}
  end

  @doc """
  Handle sending a voice note in a room
  """
  def send_room_voice_note(socket, %{"encrypted_content" => content, "nonce" => nonce, "duration_ms" => duration}) do
    room = socket.assigns[:room]
    current_user = socket.assigns[:current_user]

    if room && current_user do
      # Decode base64 strings to binary for proper storage
      decoded_content = Base.decode64!(content)
      decoded_nonce = Base.decode64!(nonce)

      case Friends.Social.send_room_message(
             room.id,
             current_user.id,
             decoded_content,
             "voice",
             %{"duration_ms" => duration},
             decoded_nonce
           ) do
        {:ok, _message} ->
          {:noreply, socket}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to send voice message")}
      end
    else
      {:noreply, socket}
    end
  end

  @doc """
  Clean up stale typing indicators (users who stopped typing but didn't send clear event)
  Called periodically or on new messages
  """
  def cleanup_stale_typing(socket) do
    typing_users = socket.assigns[:typing_users] || %{}
    now = System.system_time(:millisecond)
    # Remove entries older than 3 seconds
    updated = typing_users
      |> Enum.reject(fn {_user_id, %{timestamp: ts}} -> now - ts > 3000 end)
      |> Map.new()

    {:noreply, assign(socket, :typing_users, updated)}
  end

  # ============================================================================
  # WARMTH PULSE
  # Broadcasts when someone hovers content - subtle ambient awareness
  # ============================================================================

  @doc """
  Handle warmth pulse - broadcast when user hovers over content
  """
  def send_warmth_pulse(socket, item_type, item_id) do
    room = socket.assigns[:room]
    current_user = socket.assigns[:current_user]

    if room && current_user do
      Phoenix.PubSub.broadcast(
        Friends.PubSub,
        "room:#{room.id}:warmth",
        {:warmth_pulse, %{
          user_id: current_user.id,
          username: current_user.username,
          item_type: item_type,
          item_id: item_id,
          timestamp: System.system_time(:millisecond)
        }}
      )
    end

    {:noreply, socket}
  end

  @doc """
  Handle incoming warmth pulse from another user
  """
  def handle_warmth_pulse(socket, %{user_id: user_id, item_type: item_type, item_id: item_id}) do
    current_user = socket.assigns[:current_user]

    # Ignore own warmth
    if current_user && user_id == current_user.id do
      {:noreply, socket}
    else
      # Track active warmth pulses for UI
      warmth_pulses = socket.assigns[:warmth_pulses] || %{}
      key = "#{item_type}-#{item_id}"
      updated = Map.put(warmth_pulses, key, System.system_time(:millisecond))

      # Schedule cleanup after 2 seconds
      Process.send_after(self(), {:clear_warmth, key}, 2000)

      {:noreply, assign(socket, :warmth_pulses, updated)}
    end
  end

  @doc """
  Clear warmth pulse after timeout
  """
  def clear_warmth(socket, key) do
    warmth_pulses = socket.assigns[:warmth_pulses] || %{}
    updated = Map.delete(warmth_pulses, key)
    {:noreply, assign(socket, :warmth_pulses, updated)}
  end

  # ============================================================================
  # VIEWING INDICATORS
  # Shows who is currently looking at what content - shared attention
  # ============================================================================

  @doc """
  Broadcast when user starts viewing a photo
  """
  def start_viewing(socket, photo_id) do
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

    {:noreply, socket}
  end

  @doc """
  Broadcast when user stops viewing a photo
  """
  def stop_viewing(socket, photo_id) do
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

    {:noreply, socket}
  end

  @doc """
  Handle incoming viewing broadcast
  """
  def handle_viewing(socket, %{user_id: user_id, username: username, photo_id: photo_id}) do
    current_user = socket.assigns[:current_user]

    # Ignore own viewing
    if current_user && user_id == current_user.id do
      {:noreply, socket}
    else
      # Track who's viewing what
      photo_viewers = socket.assigns[:photo_viewers] || %{}
      viewers_for_photo = Map.get(photo_viewers, photo_id, [])
      
      # Add viewer if not already there
      viewer = %{user_id: user_id, username: username}
      updated_viewers = 
        if Enum.any?(viewers_for_photo, &(&1.user_id == user_id)) do
          viewers_for_photo
        else
          [viewer | viewers_for_photo]
        end
      
      updated = Map.put(photo_viewers, photo_id, updated_viewers)
      {:noreply, assign(socket, :photo_viewers, updated)}
    end
  end

  @doc """
  Handle user stopped viewing
  """
  def handle_stopped_viewing(socket, %{user_id: user_id, photo_id: photo_id}) do
    photo_viewers = socket.assigns[:photo_viewers] || %{}
    viewers_for_photo = Map.get(photo_viewers, photo_id, [])
    
    updated_viewers = Enum.reject(viewers_for_photo, &(&1.user_id == user_id))
    updated = Map.put(photo_viewers, photo_id, updated_viewers)
    
    {:noreply, assign(socket, :photo_viewers, updated)}
  end

  # ============================================================================
  # WALKIE-TALKIE MODE
  # Hold-to-speak live audio streaming via PubSub
  # ============================================================================

  @doc """
  Broadcast walkie-talkie audio chunk to room
  """
  def send_walkie_chunk(socket, %{"encrypted_audio" => audio, "nonce" => nonce}) do
    room = socket.assigns[:room]
    current_user = socket.assigns[:current_user]

    if room && current_user do
      Phoenix.PubSub.broadcast(
        Friends.PubSub,
        "room:#{room.id}:walkie",
        {:walkie_chunk, %{
          user_id: current_user.id,
          username: current_user.username,
          encrypted_audio: audio,
          nonce: nonce
        }}
      )
    end

    {:noreply, socket}
  end

  @doc """
  Broadcast walkie start signal
  """
  def send_walkie_start(socket) do
    room = socket.assigns[:room]
    current_user = socket.assigns[:current_user]

    if room && current_user do
      Phoenix.PubSub.broadcast(
        Friends.PubSub,
        "room:#{room.id}:walkie",
        {:walkie_start, %{
          user_id: current_user.id,
          username: current_user.username
        }}
      )
    end

    {:noreply, assign(socket, :walkie_active_user, current_user.id)}
  end

  @doc """
  Broadcast walkie stop signal
  """
  def send_walkie_stop(socket) do
    room = socket.assigns[:room]
    current_user = socket.assigns[:current_user]

    if room && current_user do
      Phoenix.PubSub.broadcast(
        Friends.PubSub,
        "room:#{room.id}:walkie",
        {:walkie_stop, %{user_id: current_user.id}}
      )
    end

    {:noreply, assign(socket, :walkie_active_user, nil)}
  end

  @doc """
  Handle incoming walkie chunk - forward to client
  """
  def handle_walkie_chunk(socket, %{user_id: user_id} = payload) do
    current_user = socket.assigns[:current_user]

    # Don't echo back to sender
    if current_user && user_id != current_user.id do
      {:noreply, push_event(socket, "walkie_chunk", payload)}
    else
      {:noreply, socket}
    end
  end

  @doc """
  Handle walkie start signal - show indicator
  """
  def handle_walkie_start(socket, %{user_id: user_id, username: username}) do
    current_user = socket.assigns[:current_user]

    if current_user && user_id != current_user.id do
      socket = socket
        |> assign(:walkie_active_user, user_id)
        |> push_event("walkie_start", %{username: username})
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @doc """
  Handle walkie stop signal
  """
  def handle_walkie_stop(socket, _payload) do
    socket = socket
      |> assign(:walkie_active_user, nil)
      |> push_event("walkie_stop", %{})
    {:noreply, socket}
  end
end

