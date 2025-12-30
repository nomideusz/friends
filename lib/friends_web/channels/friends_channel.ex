defmodule FriendsWeb.FriendsChannel do
  @moduledoc """
  Channel for real-time social graph updates.
  Broadcasts friend connections, new users, etc.
  """
  use Phoenix.Channel
  require Logger
  
  @impl true
  def join("friends:global", _payload, socket) do
    # Subscribe to global friend updates
    :ok = Phoenix.PubSub.subscribe(Friends.PubSub, "friends:global")
    Logger.info("[FriendsChannel] Client joined friends:global")
    {:ok, socket}
  end

  def join("friends:user:" <> user_id, _payload, socket) do
    # Subscribe to user-specific updates
    :ok = Phoenix.PubSub.subscribe(Friends.PubSub, "friends:user:#{user_id}")
    Logger.info("[FriendsChannel] Client joined friends:user:#{user_id}")
    {:ok, socket}
  end

  def join(_topic, _payload, _socket) do
    {:error, %{reason: "unauthorized"}}
  end

  # Forward PubSub messages to the channel
  @impl true
  def handle_info({:friend_accepted, data}, socket) do
    Logger.info("[FriendsChannel] Received :friend_accepted event")
    push(socket, "friend_accepted", format_friendship(data))
    {:noreply, socket}
  end

  def handle_info({:friend_removed, data}, socket) do
    Logger.info("[FriendsChannel] Received :friend_removed event")
    push(socket, "friend_removed", format_friendship(data))
    {:noreply, socket}
  end

  def handle_info({:friend_request, data}, socket) do
    Logger.info("[FriendsChannel] Received :friend_request event")
    push(socket, "friend_request", format_friendship(data))
    {:noreply, socket}
  end

  def handle_info({:welcome_new_user, data}, socket) do
    Logger.info("[FriendsChannel] Broadcasting welcome_new_user: #{inspect(data)}")
    push(socket, "welcome_new_user", data)
    {:noreply, socket}
  end

  def handle_info({:welcome_user_deleted, data}, socket) do
    push(socket, "welcome_user_deleted", data)
    {:noreply, socket}
  end

  def handle_info({:welcome_signal, data}, socket) do
    push(socket, "welcome_signal", data)
    {:noreply, socket}
  end

  def handle_info(msg, socket) do
    Logger.debug("[FriendsChannel] Received unknown message: #{inspect(msg)}")
    {:noreply, socket}
  end

  # Handle struct (Friendship schema)
  defp format_friendship(%Friends.Social.Friendship{} = f) do
    %{
      user_id: f.user_id,
      friend_user_id: f.friend_user_id,
      from_id: f.user_id,
      to_id: f.friend_user_id
    }
  end

  defp format_friendship(%{user_id: user_id, friend_user_id: friend_user_id}) do
    %{
      user_id: user_id,
      friend_user_id: friend_user_id,
      from_id: user_id,
      to_id: friend_user_id
    }
  end

  defp format_friendship(data) when is_struct(data) do
    # Generic struct handling
    %{
      user_id: Map.get(data, :user_id),
      friend_user_id: Map.get(data, :friend_user_id),
      from_id: Map.get(data, :user_id),
      to_id: Map.get(data, :friend_user_id)
    }
  end

  defp format_friendship(data), do: data
end
