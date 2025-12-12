defmodule Friends.Repo.Migrations.CreateDmRoomsForExistingFriendships do
  use Ecto.Migration
  import Ecto.Query

  def up do
    # Get all accepted friendships
    friendships = Friends.Repo.all(
      from f in "friends_friendships",
        where: f.status == "accepted",
        select: {f.user_id, f.friend_user_id}
    )

    # Create DM rooms for each friendship (if not exists)
    Enum.each(friendships, fn {user1_id, user2_id} ->
      {lower, higher} = if user1_id < user2_id, do: {user1_id, user2_id}, else: {user2_id, user1_id}
      code = "dm-#{lower}-#{higher}"
      
      # Check if DM room already exists
      existing = Friends.Repo.one(
        from r in "friends_rooms",
          where: r.code == ^code,
          select: r.id
      )
      
      if is_nil(existing) do
        # Get usernames for room name
        user1 = Friends.Repo.one(from u in "friends_users", where: u.id == ^user1_id, select: u.username)
        user2 = Friends.Repo.one(from u in "friends_users", where: u.id == ^user2_id, select: u.username)
        name = "#{user1 || "user"} & #{user2 || "user"}"
        
        now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
        
        # Create the room
        {:ok, %{id: room_id}} = Friends.Repo.insert_all("friends_rooms", [
          %{
            code: code,
            name: name,
            is_private: true,
            room_type: "dm",
            inserted_at: now,
            updated_at: now
          }
        ], returning: [:id])
        |> case do
          {1, [result]} -> {:ok, result}
          _ -> {:error, :insert_failed}
        end
        
        # Add both users as members
        Friends.Repo.insert_all("friends_room_members", [
          %{room_id: room_id, user_id: user1_id, role: "member", inserted_at: now, updated_at: now},
          %{room_id: room_id, user_id: user2_id, role: "member", inserted_at: now, updated_at: now}
        ])
      end
    end)
  end

  def down do
    # Remove all DM rooms
    Friends.Repo.delete_all(
      from r in "friends_rooms",
        where: r.room_type == "dm"
    )
  end
end
