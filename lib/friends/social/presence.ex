defmodule Friends.Social.Presence do
  @moduledoc """
  Real-time presence tracking for rooms and global online status.
  """
  use Phoenix.Presence,
    otp_app: :friends,
    pubsub_server: Friends.PubSub

  @global_topic "friends:presence:global"

  # ============================================================================
  # ROOM PRESENCE (existing)
  # ============================================================================

  @doc """
  Track a user in a room.
  """
  def track_user(socket, room_code, user_id, user_color, user_name \\ nil) do
    track(socket, "friends:presence:#{room_code}", user_id, %{
      user_id: user_id,
      user_color: user_color,
      user_name: user_name,
      joined_at: System.system_time(:second)
    })
  end

  @doc """
  Update user presence metadata.
  """
  def update_user(socket, room_code, user_id, user_color, user_name) do
    update(socket, "friends:presence:#{room_code}", user_id, fn meta ->
      %{
        user_id: user_id,
        user_color: user_color,
        user_name: user_name,
        joined_at: Map.get(meta, :joined_at, System.system_time(:second))
      }
    end)
  end

  @doc """
  Untrack a user from a room.
  """
  def untrack_user(socket, room_code, user_id) do
    untrack(socket, "friends:presence:#{room_code}", user_id)
  end

  @doc """
  Get all users in a room.
  """
  def list_users(room_code) do
    list("friends:presence:#{room_code}")
    |> Enum.map(fn {_user_id, %{metas: [meta | _]}} -> meta end)
  end

  @doc """
  Check if name is taken in room.
  """
  def name_taken?(room_code, name, exclude_user_id) do
    list_users(room_code)
    |> Enum.any?(fn user ->
      user.user_name == name && user.user_id != exclude_user_id
    end)
  end

  # ============================================================================
  # GLOBAL PRESENCE (new - for breathing avatars)
  # ============================================================================

  @doc """
  Track a user globally (visible to all their friends).
  Call this on mount to show user as online anywhere in the app.
  """
  def track_global(pid, user_id, user_color, user_name) do
    track(pid, @global_topic, "user-#{user_id}", %{
      user_id: user_id,
      user_color: user_color,
      user_name: user_name,
      online_at: System.system_time(:second)
    })
  end

  @doc """
  Untrack a user from global presence.
  """
  def untrack_global(pid, user_id) do
    untrack(pid, @global_topic, "user-#{user_id}")
  end

  @doc """
  Get all online user IDs.
  """
  def list_online_user_ids do
    list(@global_topic)
    |> Enum.map(fn {"user-" <> id_str, _} -> 
      case Integer.parse(id_str) do
        {id, ""} -> id
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Filter a list of friend user IDs to only those currently online.
  """
  def filter_online(friend_ids) when is_list(friend_ids) do
    online_ids = MapSet.new(list_online_user_ids())
    Enum.filter(friend_ids, &MapSet.member?(online_ids, &1))
  end

  @doc """
  Check if a specific user is online.
  """
  def online?(user_id) do
    user_id in list_online_user_ids()
  end

  @doc """
  Subscribe to global presence changes.
  """
  def subscribe_global do
    Phoenix.PubSub.subscribe(Friends.PubSub, @global_topic)
  end

  @doc """
  Get the global topic name.
  """
  def global_topic, do: @global_topic
end

