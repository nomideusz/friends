defmodule Friends.Social.Presence do
  @moduledoc """
  Real-time presence tracking for rooms.
  """
  use Phoenix.Presence,
    otp_app: :friends,
    pubsub_server: Friends.PubSub

  @doc """
  Track a user in a room.
  """
  def track_user(socket, room_code, user_id, user_color, user_name \\ nil) do
    track(socket, room_code, user_id, %{
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
    update(socket, room_code, user_id, fn meta ->
      %{
        user_id: user_id,
        user_color: user_color,
        user_name: user_name,
        joined_at: Map.get(meta, :joined_at, System.system_time(:second))
      }
    end)
  end

  @doc """
  Get all users in a room.
  """
  def list_users(room_code) do
    list(room_code)
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
end

