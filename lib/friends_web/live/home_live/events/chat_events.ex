defmodule FriendsWeb.HomeLive.Events.ChatEvents do
  @moduledoc """
  Event handlers for Chat UI interactions.
  Includes live typing feature for real-time presence.
  """
  import Phoenix.Component
  # import Phoenix.LiveView

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
end

