defmodule Friends.Social.Rooms do
  @moduledoc """
  Manages Room lifecycle, creation, access control, and membership.
  """
  import Ecto.Query, warn: false
  alias Friends.Repo
  alias Friends.Social.{Room, RoomMember, Photo, Note, User}

  # --- Room Creation & Retrieval ---

  def get_or_create_public_square do
    case Repo.get_by(Room, code: "lobby") do
      nil ->
        {:ok, room} = create_room(%{code: "lobby", name: "public square"})
        room

      room ->
        # Always ensure name is "public square"
        if room.name != "public square" do
          room
          |> Room.changeset(%{name: "public square"})
          |> Repo.update!()
        else
          room
        end
    end
  end

  def get_room_by_code(code) do
    Repo.get_by(Room, code: code) |> Repo.preload([:owner])
  end

  def get_room(id), do: Repo.get(Room, id)

  def create_room(attrs) do
    result =
      %Room{}
      |> Room.changeset(attrs)
      |> Repo.insert()

    # Broadcast to all users so public rooms appear in their dropdowns
    case result do
      {:ok, room} when not room.is_private ->
        Phoenix.PubSub.broadcast(Friends.PubSub, "friends:rooms", {:public_room_created, room})
        {:ok, room}

      _ ->
        result
    end
  end

  def create_room(user, attrs) do
    result =
      %Room{}
      |> Room.changeset(Map.put(attrs, "created_by", user.id))
      |> Ecto.Changeset.put_assoc(:owner, user)
      |> Repo.insert()

    case result do
      {:ok, room} ->
        # Auto-join owner
        join_room(user, room.code)
        {:ok, room}

      error ->
        error
    end
  end

  def create_private_room(attrs, owner_id) do
    result =
      Repo.transaction(fn ->
        room_attrs =
          Map.merge(attrs, %{is_private: true, owner_id: owner_id, room_type: "private"})

        case create_room(room_attrs) do
          {:ok, room} ->
            # Add owner as member
            {:ok, _member} = add_room_member(room.id, owner_id, "owner")
            room

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
      end)

    # Broadcast so owner's room list updates in real-time
    case result do
      {:ok, room} ->
        Phoenix.PubSub.broadcast(
          Friends.PubSub,
          "friends:user:#{owner_id}",
          {:room_created, room}
        )

        {:ok, room}

      error ->
        error
    end
  end

  def generate_room_code do
    words = ~w(swift calm warm cool soft deep wild free bold pure)
    nouns = ~w(wave tide peak vale cove glen bay dune reef isle)

    word = Enum.random(words)
    noun = Enum.random(nouns)
    num = :rand.uniform(99)

    "#{word}-#{noun}-#{num}"
  end

  def list_public_rooms(limit \\ 20) do
    # Get rooms with photo/note counts and last activity
    Repo.all(
      from r in Room,
        left_join: p in Photo,
        on: p.room_id == r.id,
        left_join: n in Note,
        on: n.room_id == r.id,
        where: r.is_private == false,
        group_by: r.id,
        order_by: [
          desc:
            fragment("GREATEST(MAX(?), MAX(?), ?)", p.inserted_at, n.inserted_at, r.inserted_at)
        ],
        limit: ^limit,
        select: %{
          id: r.id,
          code: r.code,
          name: r.name,
          photo_count: count(p.id, :distinct),
          note_count: count(n.id, :distinct),
          last_activity:
            fragment("GREATEST(MAX(?), MAX(?), ?)", p.inserted_at, n.inserted_at, r.inserted_at)
        }
    )
  end

  # --- Room Access ---

  def can_access_room?(room, user_id) when is_nil(user_id) do
    # Anonymous users can only access public rooms
    not room.is_private
  end

  def can_access_room?(room, user_id) when is_binary(user_id) do
    # Extract numeric ID from "user-123" format
    case extract_user_id(user_id) do
      nil -> not room.is_private
      numeric_id -> can_access_room?(room, numeric_id)
    end
  end

  def can_access_room?(room, user_id) when is_integer(user_id) do
    if room.is_private do
      # Check if user is a member
      Repo.exists?(
        from rm in RoomMember,
          where: rm.room_id == ^room.id and rm.user_id == ^user_id
      )
    else
      true
    end
  end

  defp extract_user_id("user-" <> id) do
    case Integer.parse(id) do
      {num, ""} -> num
      _ -> nil
    end
  end

  defp extract_user_id(_), do: nil

  # --- Room Members ---

  def add_room_member(room_id, user_id, role \\ "member", invited_by_id \\ nil) do
    result =
      %RoomMember{}
      |> RoomMember.changeset(%{
        room_id: room_id,
        user_id: user_id,
        role: role,
        invited_by_id: invited_by_id
      })
      |> Repo.insert()

    # Broadcast to the new member so their room list updates in real-time
    case result do
      {:ok, _member} ->
        room = get_room(room_id)

        if room do
          Phoenix.PubSub.broadcast(
            Friends.PubSub,
            "friends:user:#{user_id}",
            {:room_created, room}
          )
        end

        result

      _ ->
        result
    end
  end

  def remove_room_member(room_id, user_id) do
    Repo.delete_all(
      from rm in RoomMember,
        where: rm.room_id == ^room_id and rm.user_id == ^user_id
    )
  end

  def list_room_members(room_id) do
    Repo.all(
      from rm in RoomMember,
        where: rm.room_id == ^room_id,
        preload: [:user]
    )
  end
  
  def get_room_member(room_id, user_id) do
    Repo.get_by(RoomMember, room_id: room_id, user_id: user_id)
  end

  def get_room_members(room_id) do
    Repo.all(
      from m in RoomMember,
        join: u in User,
        on: m.user_id == u.id,
        where: m.room_id == ^room_id,
        select: %{user: u, role: m.role, joined_at: m.inserted_at}
    )
  end

  def join_room(user, room_code) do
    case get_room_by_code(room_code) do
      nil ->
        {:error, :room_not_found}

      room ->
        result =
          %RoomMember{}
          |> RoomMember.changeset(%{
            room_id: room.id,
            user_id: user.id,
            role: "member"
          })
          |> Repo.insert()
          |> case do
            # Return room for easy redirect
            {:ok, _member} ->
              {:ok, room}

            {:error, changeset} ->
              # Check if already member
              if changeset.errors[:user_id] do
                # Already member, just return room
                {:ok, room}
              else
                {:error, changeset}
              end
          end

        # Broadcast so user's room list updates in real-time (for private rooms)
        case result do
          {:ok, room} when room.is_private ->
            Phoenix.PubSub.broadcast(
              Friends.PubSub,
              "friends:user:#{user.id}",
              {:room_created, room}
            )

            {:ok, room}

          {:ok, room} ->
            {:ok, room}

          error ->
            error
        end
    end
  end

  def leave_room(user, room_id) do
    from(m in RoomMember, where: m.user_id == ^user.id and m.room_id == ^room_id)
    |> Repo.delete_all()
  end
  
  def invite_to_room(room_id, inviter_user_id, invitee_user_id) do
    # Check if inviter has permission
    case get_room_member(room_id, inviter_user_id) do
      nil ->
        {:error, :not_a_member}

      member when member.role in ["owner", "admin"] ->
        add_room_member(room_id, invitee_user_id, "member", inviter_user_id)

      _ ->
        {:error, :not_authorized}
    end
  end

  # --- User Room Lists ---

  def list_user_private_rooms(user_id) do
    Repo.all(
      from r in Room,
        join: rm in RoomMember,
        on: rm.room_id == r.id,
        where: rm.user_id == ^user_id and r.is_private == true,
        order_by: [desc: r.updated_at]
    )
  end

  def list_user_dashboard_rooms(user_id) do
    rooms =
      Repo.all(
        from r in Room,
          join: rm in RoomMember,
          on: rm.room_id == r.id,
          where: rm.user_id == ^user_id and r.is_private == true,
          order_by: [desc: r.updated_at],
          preload: [members: :user]
      )

    Enum.map(rooms, fn room ->
      if room.room_type == "dm" do
        other_member = Enum.find(room.members, fn m -> m.user_id != user_id end)
        name = if other_member && other_member.user, do: other_member.user.username, else: "User"
        %{room | name: name}
      else
        room
      end
    end)
  end
  
  def list_user_rooms(user_id) do
    Repo.all(
      from r in Room,
        join: m in RoomMember,
        on: m.room_id == r.id,
        where: m.user_id == ^user_id,
        order_by: [desc: m.inserted_at],
        preload: [:owner, :members]
    )
  end

  def list_user_groups(user_id) do
    Repo.all(
      from r in Room,
        join: m in RoomMember,
        on: m.room_id == r.id,
        where: m.user_id == ^user_id and r.room_type == "private",
        order_by: [desc: m.inserted_at],
        preload: [:owner, :members]
    )
  end

  def list_user_dms(user_id) do
    Repo.all(
      from r in Room,
        join: m in RoomMember,
        on: m.room_id == r.id,
        join: u in User,
        on: m.user_id == u.id,
        # Find the room type
        where: m.user_id == ^user_id and r.room_type == "dm",
        # Preload members to find the other user later
        preload: [members: :user],
        order_by: [desc: m.inserted_at]
    )
  end

  def list_user_room_ids(user_id) do
    Repo.all(
      from rm in RoomMember,
        where: rm.user_id == ^user_id,
        select: rm.room_id
    )
  end

  # --- DM Rooms ---
  
  # Using friends.social.rooms for DM rooms makes sense as they are rooms

  def dm_room_code(user1_id, user2_id) when is_integer(user1_id) and is_integer(user2_id) do
    {lower, higher} = if user1_id < user2_id, do: {user1_id, user2_id}, else: {user2_id, user1_id}
    "dm-#{lower}-#{higher}"
  end

  def get_or_create_dm_room(user1_id, user2_id) do
    Friends.Social.get_user(user1_id) # Ensure simple alias usage if needed, or rely on implementation
    # Implementation of get_or_create_dm_room needs get_dm_room and create_dm_room
    
    # We need to handle string/int conversion here or let caller handle it.
    # Original social.ex handled binaries.
    
    do_get_or_create_dm_room(user1_id, user2_id)
  end
  
  defp do_get_or_create_dm_room(user1_id, user2_id) when is_binary(user1_id),
    do: do_get_or_create_dm_room(String.to_integer(user1_id), user2_id)

  defp do_get_or_create_dm_room(user1_id, user2_id) when is_binary(user2_id),
    do: do_get_or_create_dm_room(user1_id, String.to_integer(user2_id))
    
  defp do_get_or_create_dm_room(user1_id, user2_id) when is_integer(user1_id) and is_integer(user2_id) do
    case get_dm_room(user1_id, user2_id) do
      nil -> create_dm_room(user1_id, user2_id)
      room -> {:ok, room}
    end
  end

  def get_dm_room(user1_id, user2_id) when is_integer(user1_id) and is_integer(user2_id) do
    code = dm_room_code(user1_id, user2_id)
    get_room_by_code(code)
  end

  def create_dm_room(user1_id, user2_id) when is_integer(user1_id) and is_integer(user2_id) do
    code = dm_room_code(user1_id, user2_id)

    # Get user names for room name - Need User repo access.
    # Since we are inside Social context, we can query User directly.
    user1 = Repo.get(User, user1_id)
    user2 = Repo.get(User, user2_id)
    name = "#{(user1 && user1.username) || "user"} & #{(user2 && user2.username) || "user"}"

    result =
      Repo.transaction(fn ->
        room_attrs = %{
          code: code,
          name: name,
          is_private: true,
          room_type: "dm"
        }

        case create_room(room_attrs) do
          {:ok, room} ->
            # Add both users as members
            {:ok, _} = add_room_member(room.id, user1_id, "member")
            {:ok, _} = add_room_member(room.id, user2_id, "member")
            room

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
      end)

    # Broadcast to both users so their room lists update in real-time
    case result do
      {:ok, room} ->
        Phoenix.PubSub.broadcast(
          Friends.PubSub,
          "friends:user:#{user1_id}",
          {:room_created, room}
        )

        Phoenix.PubSub.broadcast(
          Friends.PubSub,
          "friends:user:#{user2_id}",
          {:room_created, room}
        )

        {:ok, room}

      error ->
        error
    end
  end
end
