defmodule Friends.Social do
  @moduledoc """
  The Social context - manages rooms, photos, notes, users, and real-time interactions.
  Identity is based on browser crypto keys with social recovery.
  """

  import Ecto.Query, warn: false
  alias Friends.Repo
  alias Friends.Social.{Room, Photo, Note, Device, User, Invite, TrustedFriend, RecoveryVote, RoomMember, Friendship, Conversation, ConversationParticipant, Message}

  def admin_username?(username) when is_binary(username) do
    admins =
      Application.get_env(:friends, :admin_usernames, [])
      |> Enum.map(&String.downcase/1)

    String.downcase(username) in admins
  end

  def admin_username?(_), do: false

  # --- PubSub ---

  defp topic(room_code), do: "friends:room:#{room_code}"

  def subscribe(room_code) do
    Phoenix.PubSub.subscribe(Friends.PubSub, topic(room_code))
  end

  def unsubscribe(room_code) do
    Phoenix.PubSub.unsubscribe(Friends.PubSub, topic(room_code))
  end

  def broadcast(room_code, event, payload) do
    Phoenix.PubSub.broadcast(Friends.PubSub, topic(room_code), {event, payload})
  end

  def broadcast(room_code, event, payload, session_id) do
    Phoenix.PubSub.broadcast(Friends.PubSub, topic(room_code), {event, payload, session_id})
  end

  # --- Rooms ---

  @doc """
  Get or create the public square - the main public room.
  Uses code "lobby" for URL compatibility but displays as "public square".
  """
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

  # Alias for backwards compatibility
  defdelegate get_or_create_lobby(), to: __MODULE__, as: :get_or_create_public_square

  def get_room_by_code(code) do
    Repo.get_by(Room, code: code) |> Repo.preload([:owner])
  end

  def get_room(id), do: Repo.get(Room, id)

  def create_room(attrs) do
    result = %Room{}
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


  def generate_room_code do
    words = ~w(swift calm warm cool soft deep wild free bold pure)
    nouns = ~w(wave tide peak vale cove glen bay dune reef isle)

    word = Enum.random(words)
    noun = Enum.random(nouns)
    num = :rand.uniform(99)

    "#{word}-#{noun}-#{num}"
  end

  @doc """
  Create a private room with the user as owner
  """
  def create_private_room(attrs, owner_id) do
    result = Repo.transaction(fn ->
      room_attrs = Map.merge(attrs, %{is_private: true, owner_id: owner_id, room_type: "private"})
      
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
        Phoenix.PubSub.broadcast(Friends.PubSub, "friends:user:#{owner_id}", {:room_created, room})
        {:ok, room}
      error ->
        error
    end
  end


  @doc """
  Check if a user can access a room
  """
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

  @doc """
  Add a member to a private room
  """
  def add_room_member(room_id, user_id, role \\ "member", invited_by_id \\ nil) do
    result = %RoomMember{}
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
          Phoenix.PubSub.broadcast(Friends.PubSub, "friends:user:#{user_id}", {:room_created, room})
        end
        result
      _ ->
        result
    end
  end


  @doc """
  Remove a member from a room
  """
  def remove_room_member(room_id, user_id) do
    Repo.delete_all(
      from rm in RoomMember,
        where: rm.room_id == ^room_id and rm.user_id == ^user_id
    )
  end

  @doc """
  List members of a room
  """
  def list_room_members(room_id) do
    Repo.all(
      from rm in RoomMember,
        where: rm.room_id == ^room_id,
        preload: [:user]
    )
  end

  @doc """
  List private rooms the user is a member of
  """
  def list_user_private_rooms(user_id) do
    Repo.all(
      from r in Room,
        join: rm in RoomMember,
        on: rm.room_id == r.id,
        where: rm.user_id == ^user_id and r.is_private == true,
        order_by: [desc: r.updated_at]
    )
  end

  @doc """
  List private rooms for the dashboard.
  For DMs, it populates `r.name` with the other user's username.
  """
  def list_user_dashboard_rooms(user_id) do
    rooms = Repo.all(
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

  @doc """
  List public rooms with activity counts, ordered by recent activity
  """
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
        order_by: [desc: fragment("GREATEST(MAX(?), MAX(?), ?)", p.inserted_at, n.inserted_at, r.inserted_at)],
        limit: ^limit,
        select: %{
          id: r.id,
          code: r.code,
          name: r.name,
          photo_count: count(p.id, :distinct),
          note_count: count(n.id, :distinct),
          last_activity: fragment("GREATEST(MAX(?), MAX(?), ?)", p.inserted_at, n.inserted_at, r.inserted_at)
        }
    )
  end

  @doc """
  Invite a user to a private room
  """
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

  @doc """
  Get a room member record
  """
  def get_room_member(room_id, user_id) do
    Repo.get_by(RoomMember, room_id: room_id, user_id: user_id)
  end

  # --- DM Rooms (1-1 Private Spaces) ---

  @doc """
  Generate a predictable DM room code for two users.
  Always uses the lower ID first to ensure consistency.
  """
  def dm_room_code(user1_id, user2_id) when is_integer(user1_id) and is_integer(user2_id) do
    {lower, higher} = if user1_id < user2_id, do: {user1_id, user2_id}, else: {user2_id, user1_id}
    "dm-#{lower}-#{higher}"
  end

  @doc """
  Get or create a DM room for two users.
  DM rooms are private rooms with exactly 2 members and room_type = "dm".
  """
  def get_or_create_dm_room(user1_id, user2_id) when is_integer(user1_id) and is_integer(user2_id) do
    case get_dm_room(user1_id, user2_id) do
      nil -> create_dm_room(user1_id, user2_id)
      room -> {:ok, room}
    end
  end
  def get_or_create_dm_room(user1_id, user2_id) when is_binary(user1_id), do: get_or_create_dm_room(String.to_integer(user1_id), user2_id)
  def get_or_create_dm_room(user1_id, user2_id) when is_binary(user2_id), do: get_or_create_dm_room(user1_id, String.to_integer(user2_id))

  @doc """
  Find existing DM room between two users.
  """
  def get_dm_room(user1_id, user2_id) when is_integer(user1_id) and is_integer(user2_id) do
    code = dm_room_code(user1_id, user2_id)
    get_room_by_code(code)
  end

  @doc """
  Create a new DM room for two users.
  Both users are automatically added as members.
  """
  def create_dm_room(user1_id, user2_id) when is_integer(user1_id) and is_integer(user2_id) do
    code = dm_room_code(user1_id, user2_id)
    
    # Get user names for room name
    user1 = get_user(user1_id)
    user2 = get_user(user2_id)
    name = "#{user1 && user1.username || "user"} & #{user2 && user2.username || "user"}"
    
    result = Repo.transaction(fn ->
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
        Phoenix.PubSub.broadcast(Friends.PubSub, "friends:user:#{user1_id}", {:room_created, room})
        Phoenix.PubSub.broadcast(Friends.PubSub, "friends:user:#{user2_id}", {:room_created, room})
        {:ok, room}
      error ->
        error
    end
  end


  # --- Photos ---

  def list_photos(room_id, limit \\ 50, opts \\ []) do
    offset_val = Keyword.get(opts, :offset, 0)

    Photo
    |> where([p], p.room_id == ^room_id)
    |> order_by([p], [desc: p.uploaded_at, desc: p.id])  # Add secondary sort for consistency
    |> limit(^limit)
    |> offset(^offset_val)
    |> select([p], %{
      id: p.id,
      user_id: p.user_id,
      user_color: p.user_color,
      user_name: p.user_name,
      thumbnail_data: p.thumbnail_data,
      content_type: p.content_type,
      file_size: p.file_size,
      description: p.description,
      uploaded_at: p.uploaded_at,
      room_id: p.room_id,
      inserted_at: p.inserted_at,
      updated_at: p.updated_at,
      image_data: fragment("CASE WHEN ? = 'audio/encrypted' THEN ? ELSE NULL END", p.content_type, p.image_data)
    })
    |> Repo.all()
  end

  @doc """
  List photos from a user's friend network (trusted friends + people who trust them)
  """
  def list_friends_photos(user_id, limit \\ 50, opts \\ []) do
    offset_val = Keyword.get(opts, :offset, 0)
    friend_user_ids = get_friend_network_ids(user_id)

    Photo
    |> where([p], p.user_id in ^friend_user_ids)
    |> order_by([p], desc: p.uploaded_at)
    |> limit(^limit)
    |> offset(^offset_val)
    |> select([p], %{
      id: p.id,
      user_id: p.user_id,
      user_color: p.user_color,
      user_name: p.user_name,
      thumbnail_data: p.thumbnail_data,
      content_type: p.content_type,
      file_size: p.file_size,
      description: p.description,
      uploaded_at: p.uploaded_at,
      room_id: p.room_id,
      inserted_at: p.inserted_at,
      updated_at: p.updated_at,
      image_data: fragment("CASE WHEN ? = 'audio/encrypted' THEN ? ELSE NULL END", p.content_type, p.image_data)
    })
    |> Repo.all()
  end

  def get_photo(id), do: Repo.get(Photo, id)

  @doc """
  Get full-size image data for a photo (used for lazy loading full images)
  """
  def get_photo_image_data(id) do
    Photo
    |> where([p], p.id == ^id)
    |> select([p], %{image_data: p.image_data, thumbnail_data: p.thumbnail_data, content_type: p.content_type})
    |> Repo.one()
  end

  def create_photo(attrs, room_code) do
    result =
      %Photo{}
      |> Photo.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, photo} ->
        broadcast(room_code, :new_photo, photo)
        {:ok, photo}

      error ->
        error
    end
  end

  def set_photo_thumbnail(photo_id, thumbnail_data, user_id, room_code)
      when is_integer(photo_id) and is_binary(thumbnail_data) do
    result = Photo
             |> where([p], p.id == ^photo_id and p.user_id == ^user_id)
             |> Repo.update_all(set: [thumbnail_data: thumbnail_data])

    case result do
      {1, _} ->
        # Successfully updated, broadcast the thumbnail update
        broadcast(room_code, :photo_thumbnail_updated, %{id: photo_id, thumbnail_data: thumbnail_data})
        :ok
      _ ->
        :error
    end
  end

  def update_photo_description(photo_id, description, user_id) do
    case Repo.get(Photo, photo_id) do
      nil ->
        {:error, :not_found}

      photo ->
        if photo.user_id == user_id do
          photo
          |> Photo.changeset(%{description: description})
          |> Repo.update()
        else
          {:error, :unauthorized}
        end
    end
  end

  def delete_photo(photo_id, room_code) do
    case Repo.get(Photo, photo_id) do
      nil ->
        {:error, :not_found}

      photo ->
        case Repo.delete(photo) do
          {:ok, _} ->
            broadcast(room_code, :photo_deleted, %{id: photo_id})
            {:ok, photo}

          error ->
            error
        end
    end
  end

  # --- Notes ---

  def list_notes(room_id, limit \\ 50, opts \\ []) do
    offset_val = Keyword.get(opts, :offset, 0)

    Note
    |> where([n], n.room_id == ^room_id)
    |> order_by([n], desc: n.inserted_at)
    |> limit(^limit)
    |> offset(^offset_val)
    |> Repo.all()
  end

  @doc """
  List notes from a user's friend network
  """
  def list_friends_notes(user_id, limit \\ 50, opts \\ []) do
    offset_val = Keyword.get(opts, :offset, 0)
    friend_user_ids = get_friend_network_ids(user_id)
    
    Note
    |> where([n], n.user_id in ^friend_user_ids)
    |> order_by([n], desc: n.inserted_at)
    |> limit(^limit)
    |> offset(^offset_val)
    |> Repo.all()
  end

  @doc """
  Get the user IDs in someone's friend network (for Friends feed).
  This uses the Friendship table (social connections) NOT TrustedFriend (recovery).
  
  Includes:
  - Friends I added (accepted)
  - Friends who added me (accepted)
  
  Excludes:
  - Self (own posts go to "Me" feed)
  """
  def get_friend_network_ids(user_id) do
    # Get friends I added (accepted)
    my_friends = Repo.all(
      from f in Friendship,
        where: f.user_id == ^user_id and f.status == "accepted",
        select: f.friend_user_id
    )
    
    # Get people who added me as friend (accepted)
    friends_of_me = Repo.all(
      from f in Friendship,
        where: f.friend_user_id == ^user_id and f.status == "accepted",
        select: f.user_id
    )
    
    # Combine (no self!), converting to string user_ids
    friend_ids = (my_friends ++ friends_of_me)
    |> Enum.uniq()
    |> Enum.map(&"user-#{&1}")
    
    friend_ids
  end

  @doc """
  List photos by a specific user (across all rooms)
  """
  def list_user_photos(user_id, limit \\ 50, opts \\ []) do
    offset_val = Keyword.get(opts, :offset, 0)
    user_id_str = if is_integer(user_id), do: "user-#{user_id}", else: user_id

    Photo
    |> where([p], p.user_id == ^user_id_str)
    |> order_by([p], desc: p.uploaded_at)
    |> limit(^limit)
    |> offset(^offset_val)
    |> select([p], %{
      id: p.id,
      user_id: p.user_id,
      user_color: p.user_color,
      user_name: p.user_name,
      thumbnail_data: p.thumbnail_data,
      content_type: p.content_type,
      file_size: p.file_size,
      description: p.description,
      uploaded_at: p.uploaded_at,
      room_id: p.room_id,
      inserted_at: p.inserted_at,
      updated_at: p.updated_at,
      image_data: fragment("CASE WHEN ? = 'audio/encrypted' THEN ? ELSE NULL END", p.content_type, p.image_data)
    })
    |> Repo.all()
  end

  @doc """
  List public photos (from public rooms only)
  """
  def list_public_photos(limit \\ 50, opts \\ []) do
    offset_val = Keyword.get(opts, :offset, 0)

    Photo
    |> join(:inner, [p], r in Room, on: p.room_id == r.id and r.is_private == false)
    |> order_by([p, _r], desc: p.uploaded_at)
    |> limit(^limit)
    |> offset(^offset_val)
    |> select([p, _r], %{
      id: p.id,
      user_id: p.user_id,
      user_color: p.user_color,
      user_name: p.user_name,
      thumbnail_data: p.thumbnail_data,
      content_type: p.content_type,
      file_size: p.file_size,
      description: p.description,
      uploaded_at: p.uploaded_at,
      room_id: p.room_id,
      inserted_at: p.inserted_at,
      updated_at: p.updated_at,
      image_data: fragment("CASE WHEN ? = 'audio/encrypted' THEN ? ELSE NULL END", p.content_type, p.image_data)
    })
    |> Repo.all()
  end

  @doc """
  List public notes (from public rooms only)
  """
  def list_public_notes(limit \\ 50, opts \\ []) do
    offset_val = Keyword.get(opts, :offset, 0)

    Note
    |> join(:inner, [n], r in Room, on: n.room_id == r.id and r.is_private == false)
    |> order_by([n, _r], desc: n.inserted_at)
    |> limit(^limit)
    |> offset(^offset_val)
    |> Repo.all()
  end

  # --- Rooms & Membership ---



  @doc """
  List rooms a user is a member of
  """
  def list_user_rooms(user_id) do
    Repo.all(
      from r in Room,
        join: m in RoomMember, on: m.room_id == r.id,
        where: m.user_id == ^user_id,
        order_by: [desc: m.inserted_at],
        preload: [:owner]
    )
  end

  @doc """
  Join a room
  """
  def join_room(user, room_code) do
    case get_room_by_code(room_code) do
      nil -> {:error, :room_not_found}
      room ->
        result = %RoomMember{}
        |> RoomMember.changeset(%{
          room_id: room.id,
          user_id: user.id,
          role: "member"
        })
        |> Repo.insert()
        |> case do
           {:ok, _member} -> {:ok, room} # Return room for easy redirect
           {:error, changeset} -> 
             # Check if already member
             if changeset.errors[:user_id] do
               {:ok, room} # Already member, just return room
             else
               {:error, changeset}
             end
        end
        
        # Broadcast so user's room list updates in real-time (for private rooms)
        case result do
          {:ok, room} when room.is_private ->
            Phoenix.PubSub.broadcast(Friends.PubSub, "friends:user:#{user.id}", {:room_created, room})
            {:ok, room}
          {:ok, room} ->
            {:ok, room}
          error ->
            error
        end
    end
  end


  @doc """
  Live room
  """
  def leave_room(user, room_id) do
    from(m in RoomMember, where: m.user_id == ^user.id and m.room_id == ^room_id)
    |> Repo.delete_all()
  end

  @doc """
  Get all members of a room
  """
  def get_room_members(room_id) do
    Repo.all(
      from m in RoomMember,
        join: u in User, on: m.user_id == u.id,
        where: m.room_id == ^room_id,
        select: %{user: u, role: m.role, joined_at: m.inserted_at}
    )
  end

  @doc """
  Create a new room
  """
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
      error -> error
    end
  end



  @doc """
  List notes by a specific user (across all rooms)
  """
  def list_user_notes(user_id, limit \\ 50, opts \\ []) do
    offset_val = Keyword.get(opts, :offset, 0)
    user_id_str = if is_integer(user_id), do: "user-#{user_id}", else: user_id

    Note
    |> where([n], n.user_id == ^user_id_str)
    |> order_by([n], desc: n.inserted_at)
    |> limit(^limit)
    |> offset(^offset_val)
    |> Repo.all()
  end

  def get_note(id), do: Repo.get(Note, id)

  def create_note(attrs, room_code) do
    result =
      %Note{}
      |> Note.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, note} ->
        broadcast(room_code, :new_note, note)
        {:ok, note}

      error ->
        error
    end
  end

  def update_note(note_id, attrs, user_id) do
    case Repo.get(Note, note_id) do
      nil ->
        {:error, :not_found}

      note ->
        cond do
          note.user_id != user_id ->
            {:error, :unauthorized}
          not Note.editable?(note) ->
            {:error, :grace_period_expired}
          true ->
            note
            |> Note.changeset(attrs)
            |> Repo.update()
        end
    end
  end

  def delete_note(note_id, user_id, room_code) do
    case Repo.get(Note, note_id) do
      nil ->
        {:error, :not_found}

      note ->
        cond do
          note.user_id != user_id ->
            {:error, :unauthorized}
          not Note.editable?(note) ->
            {:error, :grace_period_expired}
          true ->
            case Repo.delete(note) do
              {:ok, _} ->
                broadcast(room_code, :note_deleted, %{id: note_id})
                {:ok, note}

              error ->
                error
            end
        end
    end
  end


  # --- Messages ---

  @doc """
  List messages in a room
  """
  def list_room_messages(room_id, limit \\ 50) do
    Repo.all(
      from m in Message,
        where: m.room_id == ^room_id,
        order_by: [asc: m.inserted_at],
        limit: ^limit,
        preload: [:sender]
    )
  end

  @doc """
  Send a message to a room
  """
  def send_room_message(room_id, sender_id, content, type \\ "text", metadata \\ %{}, nonce \\ nil) do
    %Message{}
    |> Message.changeset(%{
      room_id: room_id,
      sender_id: sender_id,
      encrypted_content: content,
      content_type: type,
      metadata: metadata,
      nonce: nonce
    })
    |> Repo.insert()
    |> case do
      {:ok, message} ->
        message = Repo.preload(message, :sender)
        broadcast_room_message(room_id, message)
        {:ok, message}

      error ->
        error
    end
  end

  def subscribe_to_room_chat(room_id) do
    Phoenix.PubSub.subscribe(Friends.PubSub, "friends:room:#{room_id}:chat")
  end

  defp broadcast_room_message(room_id, message) do
    Phoenix.PubSub.broadcast(
      Friends.PubSub,
      "friends:room:#{room_id}:chat",
      {:new_room_message, message}
    )
  end


  # --- Devices (Identity) ---

  def register_device(fingerprint, browser_id) do
    case Repo.get_by(Device, browser_id: browser_id) do
      nil ->
        # Check if fingerprint exists on another browser (same device, different browser)
        existing =
          Repo.one(
            from d in Device,
              where: d.fingerprint == ^fingerprint and d.browser_id != ^browser_id,
              limit: 1
          )

        status = if existing, do: :same_device, else: :new

        {:ok, device} =
          %Device{}
          |> Device.changeset(%{
            fingerprint: fingerprint,
            browser_id: browser_id,
            master_id: existing && existing.master_id || Ecto.UUID.generate()
          })
          |> Repo.insert()

        {:ok, device, status}

      device ->
        # Update fingerprint if changed
        if device.fingerprint != fingerprint do
          device
          |> Device.changeset(%{fingerprint: fingerprint})
          |> Repo.update()
        end
        {:ok, device, :existing}
    end
  end

  def get_device_by_browser(browser_id) do
    Repo.get_by(Device, browser_id: browser_id)
  end

  def save_username(browser_id, name) do
    case get_device_by_browser(browser_id) do
      nil ->
        {:error, :not_found}

      device ->
        device
        |> Device.changeset(%{user_name: name})
        |> Repo.update()
    end
  end

  def username_taken?(name, exclude_master_id) do
    query =
      from d in Device,
        where: d.user_name == ^name and d.master_id != ^exclude_master_id,
        limit: 1

    Repo.exists?(query)
  end

  # --- Users (Crypto Identity) ---

  @doc """
  Register a new user with username and public key.
  Invite code is optional - if provided, creates mutual trust with inviter.
  """
  def register_user(attrs) do
    invite_code = attrs[:invite_code] || attrs["invite_code"]
    username = attrs[:username] || attrs["username"]

    cond do
      admin_username?(username) ->
        # Bootstrap/admin path: allow configured admin usernames without an invite.
        # If user already exists, rotate its public key to the provided one.
        case Repo.get_by(User, username: username) do
          nil ->
            create_user(attrs, %{created_by_id: nil})

          user ->
            user
            |> User.changeset(%{public_key: attrs[:public_key] || attrs["public_key"]})
            |> Repo.update()
        end

      invite_code && invite_code != "" ->
        # Registration with invite code - creates mutual trust with inviter
        with {:ok, invite} <- validate_invite(invite_code),
             {:ok, user} <- create_user(attrs, invite) do
          # Mark invite as used (skip for admin invite which has no ID)
          if invite.id, do: use_invite(invite, user)
          # Create mutual trust between inviter and invitee
          if invite.created_by_id do
            create_mutual_trust(invite.created_by_id, user.id)
          end
          {:ok, user}
        end

      true ->
        # Open registration without invite code
        create_user(attrs, %{created_by_id: nil})
    end
  end

  # Create mutual trust between two users (for invite-based registration)
  defp create_mutual_trust(user_a_id, user_b_id) do
    now = DateTime.utc_now()

    # A trusts B
    %TrustedFriend{}
    |> TrustedFriend.changeset(%{
      user_id: user_a_id,
      trusted_user_id: user_b_id,
      status: "confirmed",
      confirmed_at: now
    })
    |> Repo.insert(on_conflict: :nothing)

    # B trusts A
    %TrustedFriend{}
    |> TrustedFriend.changeset(%{
      user_id: user_b_id,
      trusted_user_id: user_a_id,
      status: "confirmed",
      confirmed_at: now
    })
    |> Repo.insert(on_conflict: :nothing)
  end

  defp create_user(attrs, invite) do
    %User{}
    |> User.changeset(Map.put(attrs, :invited_by_id, invite.created_by_id))
    |> Repo.insert()
  end

  @doc """
  Get user by public key (for authentication)
  """
  def get_user_by_public_key(public_key) when is_map(public_key) do
    # Compare the key components (x, y coordinates for ECDSA)
    Repo.one(
      from u in User,
        where: fragment("?->>'x' = ? AND ?->>'y' = ?", 
                        u.public_key, ^public_key["x"],
                        u.public_key, ^public_key["y"]),
        limit: 1
    )
  end

  def get_user_by_public_key(_), do: nil

  @doc """
  Get a user by ID.
  """
  def get_user(id) when is_integer(id) do
    Repo.get(User, id)
  end
  def get_user(id) when is_binary(id) do
    case Integer.parse(id) do
      {int_id, _} -> Repo.get(User, int_id)
      :error -> nil
    end
  end
  def get_user(_), do: nil

  @doc """
  Search for users by username or display name.
  Excludes the current user from results.
  """
  def search_users(query, current_user_id) when is_binary(query) and byte_size(query) >= 2 do
    pattern = "%#{query}%"
    Repo.all(
      from u in User,
        where: u.id != ^current_user_id and
               (ilike(u.username, ^pattern) or ilike(u.display_name, ^pattern)),
        order_by: [asc: u.username],
        limit: 20
    )
  end
  def search_users(_, _), do: []

  @doc """
  Generate a random challenge for authentication
  """
  def generate_auth_challenge do
    :crypto.strong_rand_bytes(32) |> Base.encode64()
  end

  @doc """
  Verify a signature against a challenge using the user's public key.
  Returns true if the signature is valid.
  """
  def verify_signature(public_key, challenge, signature_base64) when is_map(public_key) do
    require Logger

    try do
      Logger.info("Verifying signature - public_key keys: #{inspect(Map.keys(public_key))}")
      Logger.info("Public key full: #{inspect(public_key)}")

      # Decode the signature from base64
      case Base.decode64(signature_base64) do
        {:ok, signature_bin} ->
          Logger.debug("Signature decoded: #{byte_size(signature_bin)} bytes")

          # The public key is in JWK format (base64url x/y)
          x_val = public_key["x"]
          y_val = public_key["y"]

          Logger.info("Attempting to decode: x=#{inspect(x_val)}, y=#{inspect(y_val)}")

          with {:ok, x} <- Base.url_decode64(x_val, padding: false),
               {:ok, y} <- Base.url_decode64(y_val, padding: false) do

            Logger.info("Public key decoded successfully: x=#{byte_size(x)} bytes, y=#{byte_size(y)} bytes")

            # Create the EC public key point (uncompressed format: 04 || x || y)
            public_key_point = <<4>> <> x <> y
            Logger.info("Public key point size: #{byte_size(public_key_point)} bytes")

            # Create the EC key structure for Erlang crypto
            # Format: [public_key_point, curve_params]
            ec_public_key = [public_key_point, :secp256r1]
            Logger.info("EC key structure created for curve secp256r1")

            # WebCrypto ECDSA may return raw (r||s) 64 bytes or DER. Handle both.
            der_signature =
              case byte_size(signature_bin) do
                64 ->
                  Logger.debug("Converting raw 64-byte signature to DER format")
                  <<r::binary-size(32), s::binary-size(32)>> = signature_bin
                  encode_der_signature(r, s)

                size ->
                  Logger.debug("Using signature as-is (#{size} bytes, assuming DER)")
                  signature_bin
              end

            Logger.info("About to call crypto.verify with challenge length: #{String.length(challenge)}, signature size: #{byte_size(der_signature)}")
            result = :crypto.verify(:ecdsa, :sha256, challenge, der_signature, ec_public_key)
            Logger.info("Signature verification result: #{inspect(result)}")
            result
          else
            error ->
              Logger.warning("Failed to decode public key: #{inspect(error)}")
              false
          end

        :error ->
          Logger.warning("Failed to decode signature from base64")
          false
      end
    rescue
      e ->
        Logger.error("Exception in verify_signature: #{inspect(e)}")
        false
    catch
      kind, reason ->
        Logger.error("Caught in verify_signature: #{inspect(kind)}, #{inspect(reason)}")
        false
    end
  end

  def verify_signature(_, _, _), do: false

  # Encode r and s values into DER format
  defp encode_der_signature(r, s) do
    r_int = encode_der_integer(r)
    s_int = encode_der_integer(s)
    sequence = r_int <> s_int
    <<0x30, byte_size(sequence)>> <> sequence
  end

  defp encode_der_integer(bytes) do
    # Remove leading zeros but keep one if the high bit is set
    bytes = :binary.bin_to_list(bytes)
    bytes = Enum.drop_while(bytes, &(&1 == 0))
    bytes = if bytes == [] or hd(bytes) >= 128, do: [0 | bytes], else: bytes
    int_bytes = :binary.list_to_bin(bytes)
    <<0x02, byte_size(int_bytes)>> <> int_bytes
  end

  @doc """
  Get user by username
  """
  def get_user_by_username(username) do
    Repo.get_by(User, username: String.downcase(username))
  end

  @doc """
  Check if username is available
  """
  def username_available?(username) do
    normalized = String.downcase(username)
    not Repo.exists?(from u in User, where: u.username == ^normalized)
  end



  @doc """
  Link a device to a user
  """
  def link_device_to_user(browser_id, user_id) do
    case get_device_by_browser(browser_id) do
      nil -> {:error, :device_not_found}
      device ->
        device
        |> Device.changeset(%{user_id: user_id})
        |> Repo.update()
    end
  end

  # --- Invites ---

  @doc """
  Validate an invite code
  """
  def validate_invite(code) when is_binary(code) do
    admin_code = Application.get_env(:friends, :admin_invite_code)

    if admin_code && code == admin_code do
      {:ok, %Invite{code: admin_code, status: "active", created_by_id: nil, expires_at: nil}}
    else
    case Repo.get_by(Invite, code: code, status: "active") do
      nil -> {:error, :invalid_invite}
      invite ->
        if invite.expires_at && DateTime.compare(DateTime.utc_now(), invite.expires_at) == :gt do
          {:error, :invite_expired}
        else
          {:ok, invite}
        end
    end
    end
  end
  def validate_invite(_), do: {:error, :invalid_invite}

  @doc """
  Create a new invite for a user
  """
  def create_invite(user_id, expires_in_days \\ 7) do
    expires_at = DateTime.utc_now() |> DateTime.add(expires_in_days * 24 * 60 * 60, :second)
    
    %Invite{}
    |> Invite.changeset(%{
      created_by_id: user_id,
      code: Invite.generate_code(),
      expires_at: expires_at
    })
    |> Repo.insert()
  end

  @doc """
  Mark invite as used
  """
  def use_invite(invite, user) do
    invite
    |> Invite.changeset(%{
      status: "used",
      used_by_id: user.id,
      used_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  @doc """
  Get user's invites
  """
  def list_user_invites(user_id) do
    Repo.all(
      from i in Invite,
        where: i.created_by_id == ^user_id,
        order_by: [desc: i.inserted_at],
        preload: [:used_by]
    )
  end

  @doc """
  Get invite by code (even if inactive)
  """
  def get_invite_by_code(code) do
    Repo.get_by(Invite, code: code)
  end

  @doc """
  Update an invite
  """
  def update_invite(%Invite{} = invite, attrs) do
    invite
    |> Invite.changeset(attrs)
    |> Repo.update()
  end

  # --- Trusted Friends ---

  @doc """
  Add a trusted friend (requires confirmation from the other user)
  """
  def add_trusted_friend(user_id, trusted_user_id) do
    if user_id == trusted_user_id do
      {:error, :cannot_trust_self}
    else
      # Check current count
      count = count_trusted_friends(user_id)
      if count >= 5 do
        {:error, :max_trusted_friends}
      else
        %TrustedFriend{}
        |> TrustedFriend.changeset(%{
          user_id: user_id,
          trusted_user_id: trusted_user_id,
          status: "pending"
        })
        |> Repo.insert()
      end
    end
  end

  @doc """
  Confirm a trusted friend request
  """
  def confirm_trusted_friend(user_id, requester_id) do
    case get_trusted_friend_request(requester_id, user_id) do
      nil -> {:error, :not_found}
      tf ->
        # Confirm the incoming request
        result = tf
        |> TrustedFriend.changeset(%{
          status: "confirmed",
          confirmed_at: DateTime.utc_now()
        })
        |> Repo.update()

        # Also create reverse trust (confirmer trusts requester) if not exists
        case result do
          {:ok, _} ->
            create_reverse_trust(user_id, requester_id)
            result
          error -> error
        end
    end
  end

  # Create reverse trust relationship (mutual trust on accept)
  defp create_reverse_trust(user_id, trusted_user_id) do
    case get_trusted_friend_request(user_id, trusted_user_id) do
      nil ->
        # Only create if under the limit
        count = count_trusted_friends(user_id)
        if count < 5 do
          %TrustedFriend{}
          |> TrustedFriend.changeset(%{
            user_id: user_id,
            trusted_user_id: trusted_user_id,
            status: "confirmed",
            confirmed_at: DateTime.utc_now()
          })
          |> Repo.insert()
        end
      existing ->
        # If pending, confirm it
        if existing.status == "pending" do
          existing
          |> TrustedFriend.changeset(%{
            status: "confirmed",
            confirmed_at: DateTime.utc_now()
          })
          |> Repo.update()
        end
    end
  end

  @doc """
  Get trusted friend request
  """
  def get_trusted_friend_request(user_id, trusted_user_id) do
    Repo.get_by(TrustedFriend, user_id: user_id, trusted_user_id: trusted_user_id)
  end

  @doc """
  List user's trusted friends (confirmed)
  """
  def list_trusted_friends(user_id) do
    Repo.all(
      from tf in TrustedFriend,
        where: tf.user_id == ^user_id and tf.status == "confirmed",
        preload: [:trusted_user]
    )
  end

  @doc """
  List pending trust requests (people who want you as trusted friend)
  """
  def list_pending_trust_requests(user_id) do
    Repo.all(
      from tf in TrustedFriend,
        where: tf.trusted_user_id == ^user_id and tf.status == "pending",
        preload: [:user]
    )
  end

  @doc """
  List pending trust requests the user has sent (outgoing).
  """
  def list_sent_trust_requests(user_id) do
    Repo.all(
      from tf in TrustedFriend,
        where: tf.user_id == ^user_id and tf.status == "pending",
        preload: [:trusted_user]
    )
  end

  @doc """
  Count confirmed trusted friends
  """
  def count_trusted_friends(user_id) do
    Repo.one(
      from tf in TrustedFriend,
        where: tf.user_id == ^user_id and tf.status == "confirmed",
        select: count(tf.id)
    )
  end

  # --- Friendships (Social Connections) ---

  @doc """
  Send a friend request to another user.
  Unlike trusted friends (for recovery), social friends have no limit.
  """
  def add_friend(user_id, friend_user_id) do
    if user_id == friend_user_id do
      {:error, :cannot_friend_self}
    else
      # Check if friendship already exists (in either direction)
      existing = get_friendship(user_id, friend_user_id) || get_friendship(friend_user_id, user_id)
      
      case existing do
        nil ->
          %Friendship{}
          |> Friendship.changeset(%{
            user_id: user_id,
            friend_user_id: friend_user_id,
            status: "pending"
          })
          |> Repo.insert()
          |> broadcast_friend_update(:friend_request, [user_id, friend_user_id])
          
        %{status: "accepted"} ->
          {:error, :already_friends}
          
        %{status: "pending", user_id: ^user_id} ->
          {:error, :request_already_sent}
          
        %{status: "pending"} = friendship ->
          # They already sent us a request - auto-accept!
          accept_friend(user_id, friendship.user_id)
          
        _ ->
          {:error, :friendship_exists}
      end
    end
  end

  @doc """
  Accept a friend request from another user.
  Also creates a DM room for the two users to chat.
  """
  def accept_friend(user_id, requester_id) do
    case get_friendship(requester_id, user_id) do
      nil -> 
        {:error, :no_pending_request}
        
      %{status: "pending"} = friendship ->
        result = friendship
        |> Friendship.changeset(%{
          status: "accepted",
          accepted_at: DateTime.utc_now()
        })
        |> Repo.update()
        
        # Auto-create DM room for the new friends
        case result do
          {:ok, _} -> 
            get_or_create_dm_room(user_id, requester_id)
          _ -> 
            :ok
        end
        
        result
        |> broadcast_friend_update(:friend_accepted, [user_id, requester_id])
        
      %{status: "accepted"} ->
        {:error, :already_friends}
        
      _ ->
        {:error, :invalid_request}
    end
  end


  @doc """
  Remove a friendship (unfriend).
  """
  def remove_friend(user_id, friend_user_id) do
    # Check both directions
    friendship = get_friendship(user_id, friend_user_id) || get_friendship(friend_user_id, user_id)
    
    case friendship do
      nil -> {:error, :not_friends}
      f -> 
        Repo.delete(f)
        |> broadcast_friend_update(:friend_removed, [user_id, friend_user_id])
    end
  end

  defp broadcast_friend_update({:ok, result}, event, user_ids) when is_list(user_ids) do
    Enum.each(user_ids, fn uid ->
      Phoenix.PubSub.broadcast(Friends.PubSub, "friends:user:#{uid}", {event, result})
    end)
    {:ok, result}
  end
  defp broadcast_friend_update(error, _, _), do: error

  @doc """
  Get a single friendship record.
  """
  def get_friendship(user_id, friend_user_id) do
    Repo.get_by(Friendship, user_id: user_id, friend_user_id: friend_user_id)
  end

  @doc """
  List all accepted friends for a user.
  """
  def list_friends(user_id) do
    # Friends I added
    my_friends = Repo.all(
      from f in Friendship,
        where: f.user_id == ^user_id and f.status == "accepted",
        preload: [:friend_user]
    )
    |> Enum.map(fn f -> %{user: f.friend_user, friendship: f, direction: :outgoing} end)
    
    # Friends who added me
    friends_of_me = Repo.all(
      from f in Friendship,
        where: f.friend_user_id == ^user_id and f.status == "accepted",
        preload: [:user]
    )
    |> Enum.map(fn f -> %{user: f.user, friendship: f, direction: :incoming} end)
    
    # Combine and dedupe by user id
    (my_friends ++ friends_of_me)
    |> Enum.uniq_by(fn %{user: u} -> u.id end)
  end

  @doc """
  List pending friend requests (people who want to be your friend).
  """
  def list_friend_requests(user_id) do
    Repo.all(
      from f in Friendship,
        where: f.friend_user_id == ^user_id and f.status == "pending",
        preload: [:user]
    )
  end

  @doc """
  List pending friend requests the user has sent (outgoing).
  """
  def list_sent_friend_requests(user_id) do
    Repo.all(
      from f in Friendship,
        where: f.user_id == ^user_id and f.status == "pending",
        preload: [:friend_user]
    )
  end

  @doc """
  Count accepted friends for a user.
  """
  def count_friends(user_id) do
    my_count = Repo.one(
      from f in Friendship,
        where: f.user_id == ^user_id and f.status == "accepted",
        select: count(f.id)
    )
    
    their_count = Repo.one(
      from f in Friendship,
        where: f.friend_user_id == ^user_id and f.status == "accepted",
        select: count(f.id)
    )
    
    my_count + their_count
  end

  # --- Recovery ---

  @doc """
  Request account recovery
  """
  def request_recovery(username) do
    case get_user_by_username(username) do
      nil -> {:error, :user_not_found}
      user ->
        user
        |> User.changeset(%{
          status: "recovering",
          recovery_requested_at: DateTime.utc_now()
        })
        |> Repo.update()
    end
  end

  @doc """
  Cast recovery vote with transaction to prevent race conditions.
  Checks for duplicate votes and uses proper isolation.
  """
  def cast_recovery_vote(recovering_user_id, voting_user_id, vote, new_public_key) do
    # Verify voter is a trusted friend first (outside transaction for fast fail)
    case get_trusted_friend_request(recovering_user_id, voting_user_id) do
      nil -> {:error, :not_trusted_friend}
      tf when tf.status != "confirmed" -> {:error, :not_confirmed_friend}
      _tf ->
        # Use transaction with serializable isolation for race condition safety
        Repo.transaction(fn ->
          # Check for duplicate vote inside transaction
          if has_voted_for_recovery?(recovering_user_id, voting_user_id) do
            Repo.rollback(:already_voted)
          end

          # Insert the vote
          case %RecoveryVote{}
               |> RecoveryVote.changeset(%{
                 recovering_user_id: recovering_user_id,
                 voting_user_id: voting_user_id,
                 vote: vote,
                 new_public_key: new_public_key
               })
               |> Repo.insert() do
            {:ok, _vote} ->
              # Check threshold inside transaction to prevent race
              check_recovery_threshold_internal(recovering_user_id, new_public_key)

            {:error, changeset} ->
              Repo.rollback({:insert_failed, changeset})
          end
        end)
        |> case do
          {:ok, result} -> result
          {:error, :already_voted} -> {:error, :already_voted}
          {:error, {:insert_failed, _}} -> {:error, :vote_failed}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  # Internal threshold check (called within transaction)
  defp check_recovery_threshold_internal(user_id, new_public_key) do
    confirm_count = Repo.one(
      from rv in RecoveryVote,
        where: rv.recovering_user_id == ^user_id
               and rv.vote == "confirm"
               and fragment("?::jsonb = ?::jsonb", rv.new_public_key, ^new_public_key),
        select: count(rv.id)
    )

    if confirm_count >= 4 do
      # Recovery successful - update public key with lock
      case Repo.one(from u in User, where: u.id == ^user_id, lock: "FOR UPDATE") do
        nil ->
          Repo.rollback(:user_not_found)

        user ->
          case user
               |> User.changeset(%{
                 public_key: new_public_key,
                 status: "active",
                 recovery_requested_at: nil
               })
               |> Repo.update() do
            {:ok, updated_user} ->
              # Clean up recovery votes
              Repo.delete_all(from rv in RecoveryVote, where: rv.recovering_user_id == ^user_id)
              {:ok, :recovered, updated_user}

            {:error, _} ->
              Repo.rollback(:update_failed)
          end
      end
    else
      {:ok, :votes_recorded, confirm_count}
    end
  end

  @doc """
  Check if recovery threshold is met (4 out of 5) - public API for status checks
  """
  def check_recovery_threshold(user_id, new_public_key) do
    confirm_count = Repo.one(
      from rv in RecoveryVote,
        where: rv.recovering_user_id == ^user_id
               and rv.vote == "confirm"
               and fragment("?::jsonb = ?::jsonb", rv.new_public_key, ^new_public_key),
        select: count(rv.id)
    )

    if confirm_count >= 4 do
      {:ok, :threshold_met, confirm_count}
    else
      {:ok, :votes_recorded, confirm_count}
    end
  end

  @doc """
  Get recovery status
  """
  def get_recovery_status(user_id) do
    votes = Repo.all(
      from rv in RecoveryVote,
        where: rv.recovering_user_id == ^user_id,
        preload: [:voting_user]
    )
    
    trusted_count = count_trusted_friends(user_id)
    confirm_votes = Enum.count(votes, & &1.vote == "confirm")
    
    %{
      votes: votes,
      trusted_friends: trusted_count,
      confirmations: confirm_votes,
      needed: 4,
      can_recover: confirm_votes >= 4
    }
  end

  @doc """
  List users that are in recovery mode and have trusted this user
  (i.e., this user can vote on their recovery)
  """
  def list_recovery_requests_for_voter(voter_user_id) do
    Repo.all(
      from u in User,
        join: tf in TrustedFriend,
        on: tf.user_id == u.id and tf.trusted_user_id == ^voter_user_id and tf.status == "confirmed",
        where: u.status == "recovering",
        select: u
    )
  end

  @doc """
  Check if user has already voted for a recovery
  """
  def has_voted_for_recovery?(recovering_user_id, voter_user_id) do
    Repo.exists?(
      from rv in RecoveryVote,
        where: rv.recovering_user_id == ^recovering_user_id and rv.voting_user_id == ^voter_user_id
    )
  end

  @doc """
  Get the latest public key being recovered (for voting)
  """
  def get_recovery_public_key(recovering_user_id) do
    Repo.one(
      from rv in RecoveryVote,
        where: rv.recovering_user_id == ^recovering_user_id,
        order_by: [desc: rv.inserted_at],
        limit: 1,
        select: rv.new_public_key
    )
  end

  # --- User Devices (Device Attestation) ---

  alias Friends.Social.UserDevice

  @doc """
  Register or update a device for a user
  """
  def register_user_device(user_id, device_fingerprint, device_name, public_key_fingerprint) do
    now = DateTime.utc_now()

    case Repo.get_by(UserDevice, user_id: user_id, device_fingerprint: device_fingerprint) do
      nil ->
        # New device
        %UserDevice{}
        |> UserDevice.changeset(%{
          user_id: user_id,
          device_fingerprint: device_fingerprint,
          device_name: device_name,
          public_key_fingerprint: public_key_fingerprint,
          first_seen_at: now,
          last_seen_at: now,
          trusted: true
        })
        |> Repo.insert()

      device ->
        # Update existing device
        device
        |> UserDevice.changeset(%{
          device_name: device_name,
          public_key_fingerprint: public_key_fingerprint,
          last_seen_at: now
        })
        |> Repo.update()
    end
  end

  @doc """
  List all devices for a user
  """
  def list_user_devices(user_id) do
    Repo.all(
      from d in UserDevice,
        where: d.user_id == ^user_id and d.revoked == false,
        order_by: [desc: d.last_seen_at]
    )
  end

  @doc """
  Revoke a device
  """
  def revoke_user_device(user_id, device_id) do
    case Repo.get(UserDevice, device_id) do
      nil ->
        {:error, :not_found}

      device ->
        if device.user_id == user_id do
          device
          |> UserDevice.changeset(%{revoked: true, trusted: false})
          |> Repo.update()
        else
          {:error, :unauthorized}
        end
    end
  end

  @doc """
  Mark a device as trusted/untrusted
  """
  def update_device_trust(user_id, device_id, trusted) do
    case Repo.get(UserDevice, device_id) do
      nil ->
        {:error, :not_found}

      device ->
        if device.user_id == user_id do
          device
          |> UserDevice.changeset(%{trusted: trusted})
          |> Repo.update()
        else
          {:error, :unauthorized}
        end
    end
  end

  @doc """
  Count trusted devices for a user
  """
  def count_trusted_devices(user_id) do
    Repo.one(
      from d in UserDevice,
        where: d.user_id == ^user_id and d.trusted == true and d.revoked == false,
        select: count(d.id)
    )
  end

  # --- WebAuthn (Hardware Keys / Biometrics) ---

  # --- WebAuthn Functions (delegated to Friends.WebAuthn) ---
  # These delegate to the proper WebAuthn implementation module

  @doc """
  Generate a WebAuthn registration challenge for a user.
  """
  defdelegate generate_webauthn_registration_challenge(user), to: Friends.WebAuthn, as: :generate_registration_challenge

  @doc """
  Generate a WebAuthn authentication challenge for a user.
  """
  defdelegate generate_webauthn_authentication_challenge(user), to: Friends.WebAuthn, as: :generate_authentication_challenge

  @doc """
  Verify a WebAuthn registration response and store the credential.
  """
  def verify_and_store_webauthn_credential(user_id, credential_data, challenge, name \\ nil) do
    attestation_response = %{
      "clientDataJSON" => credential_data["response"]["clientDataJSON"],
      "attestationObject" => credential_data["response"]["attestationObject"],
      "id" => credential_data["rawId"],
      "transports" => credential_data["transports"] || []
    }

    case Friends.WebAuthn.verify_registration(attestation_response, challenge, user_id) do
      {:ok, cred_data} ->
        Friends.WebAuthn.store_credential(cred_data, name)
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Verify a WebAuthn authentication assertion.
  """
  def verify_webauthn_assertion(user_id, assertion_data, challenge) do
    assertion_response = %{
      "clientDataJSON" => assertion_data["response"]["clientDataJSON"],
      "authenticatorData" => assertion_data["response"]["authenticatorData"],
      "signature" => assertion_data["response"]["signature"],
      "id" => assertion_data["rawId"]
    }

    Friends.WebAuthn.verify_authentication(assertion_response, challenge, user_id)
  end

  @doc """
  List WebAuthn credentials for a user.
  """
  defdelegate list_webauthn_credentials(user_id), to: Friends.WebAuthn, as: :list_credentials

  @doc """
  Delete a WebAuthn credential.
  """
  def delete_webauthn_credential(user_id, credential_id) do
    Friends.WebAuthn.delete_credential(user_id, credential_id)
  end

  @doc """
  Check if a user has WebAuthn credentials registered.
  """
  defdelegate has_webauthn_credentials?(user_id), to: Friends.WebAuthn, as: :has_credentials?

  # --- Messaging (E2E Encrypted DMs) ---

  defp conversation_topic(conversation_id), do: "friends:conversation:#{conversation_id}"

  @doc """
  Subscribe to a conversation for real-time updates.
  """
  def subscribe_to_conversation(conversation_id) do
    Phoenix.PubSub.subscribe(Friends.PubSub, conversation_topic(conversation_id))
  end

  @doc """
  Subscribe to all of a user's conversations.
  """
  def subscribe_to_user_conversations(user_id) do
    Phoenix.PubSub.subscribe(Friends.PubSub, "friends:user_messages:#{user_id}")
  end

  @doc """
  Get or create a direct conversation between two users.
  """
  def get_or_create_direct_conversation(user_a_id, user_b_id) do
    # Ensure consistent ordering for lookup
    [first_id, second_id] = Enum.sort([user_a_id, user_b_id])

    # Look for existing direct conversation with exactly these two participants
    existing = Repo.one(
      from c in Conversation,
        join: p1 in ConversationParticipant, on: p1.conversation_id == c.id,
        join: p2 in ConversationParticipant, on: p2.conversation_id == c.id,
        where: c.type == "direct" and
               p1.user_id == ^first_id and
               p2.user_id == ^second_id,
        group_by: c.id,
        having: count(fragment("DISTINCT ?", p1.id)) + count(fragment("DISTINCT ?", p2.id)) == 2,
        limit: 1
    )

    case existing do
      nil -> create_conversation(user_a_id, [user_b_id], "direct", nil)
      conversation -> {:ok, Repo.preload(conversation, [:participants])}
    end
  end

  @doc """
  Create a new conversation (direct or group).
  """
  def create_conversation(creator_id, participant_ids, type \\ "direct", name \\ nil) do
    all_participant_ids = Enum.uniq([creator_id | participant_ids])

    Repo.transaction(fn ->
      {:ok, conversation} =
        %Conversation{}
        |> Conversation.changeset(%{
          type: type,
          name: name,
          created_by_id: creator_id
        })
        |> Repo.insert()

      # Add all participants
      Enum.each(all_participant_ids, fn user_id ->
        role = if user_id == creator_id, do: "owner", else: "member"

        %ConversationParticipant{}
        |> ConversationParticipant.changeset(%{
          conversation_id: conversation.id,
          user_id: user_id,
          role: role
        })
        |> Repo.insert!()
      end)

      Repo.preload(conversation, [:participants])
    end)
  end

  @doc """
  List all conversations for a user with latest message preview.
  """
  def list_user_conversations(user_id) do
    Repo.all(
      from c in Conversation,
        join: p in ConversationParticipant, on: p.conversation_id == c.id,
        where: p.user_id == ^user_id,
        preload: [participants: :user],
        order_by: [desc: c.updated_at]
    )
    |> Enum.map(fn conv ->
      # Get the latest message for preview
      latest_message = get_latest_message(conv.id)
      unread_count = get_unread_count(conv.id, user_id)
      
      Map.merge(conv, %{
        latest_message: latest_message,
        unread_count: unread_count
      })
    end)
  end

  @doc """
  Get the latest message in a conversation.
  """
  def get_latest_message(conversation_id) do
    Repo.one(
      from m in Message,
        where: m.conversation_id == ^conversation_id,
        order_by: [desc: m.inserted_at],
        limit: 1,
        preload: [:sender]
    )
  end

  @doc """
  Get unread message count for a user in a conversation.
  """
  def get_unread_count(conversation_id, user_id) do
    participant = Repo.one(
      from p in ConversationParticipant,
        where: p.conversation_id == ^conversation_id and p.user_id == ^user_id
    )

    case participant do
      nil -> 0
      %{last_read_at: nil} ->
        Repo.aggregate(
          from(m in Message, where: m.conversation_id == ^conversation_id and m.sender_id != ^user_id),
          :count
        )
      %{last_read_at: last_read} ->
        Repo.aggregate(
          from(m in Message,
            where: m.conversation_id == ^conversation_id and
                   m.sender_id != ^user_id and
                   m.inserted_at > ^last_read),
          :count
        )
    end
  end

  @doc """
  Send a message to a conversation.
  """
  def send_message(conversation_id, sender_id, encrypted_content, content_type, metadata \\ %{}, nonce, reply_to_id \\ nil) do
    # Verify sender is a participant
    participant = Repo.one(
      from p in ConversationParticipant,
        where: p.conversation_id == ^conversation_id and p.user_id == ^sender_id
    )

    if is_nil(participant) do
      {:error, :not_a_participant}
    else
      result =
        %Message{}
        |> Message.changeset(%{
          conversation_id: conversation_id,
          sender_id: sender_id,
          encrypted_content: encrypted_content,
          content_type: content_type,
          metadata: metadata,
          nonce: nonce,
          reply_to_id: reply_to_id
        })
        |> Repo.insert()

      case result do
        {:ok, message} ->
          # Update conversation's updated_at
          Repo.update_all(
            from(c in Conversation, where: c.id == ^conversation_id),
            set: [updated_at: DateTime.utc_now()]
          )

          message = Repo.preload(message, [:sender])

          # Broadcast to conversation
          Phoenix.PubSub.broadcast(
            Friends.PubSub,
            conversation_topic(conversation_id),
            {:new_message, message}
          )

          # Notify all participants
          participants = Repo.all(
            from p in ConversationParticipant,
              where: p.conversation_id == ^conversation_id and p.user_id != ^sender_id,
              select: p.user_id
          )

          Enum.each(participants, fn user_id ->
            Phoenix.PubSub.broadcast(
              Friends.PubSub,
              "friends:user_messages:#{user_id}",
              {:new_message_notification, %{conversation_id: conversation_id, message: message}}
            )
          end)

          {:ok, message}

        error -> error
      end
    end
  end

  @doc """
  List messages in a conversation with pagination.
  """
  def list_messages(conversation_id, limit \\ 50, offset \\ 0) do
    Repo.all(
      from m in Message,
        where: m.conversation_id == ^conversation_id,
        order_by: [desc: m.inserted_at],
        limit: ^limit,
        offset: ^offset,
        preload: [:sender, :reply_to]
    )
    |> Enum.reverse()  # Return in chronological order
  end

  @doc """
  Mark a conversation as read for a user.
  """
  def mark_conversation_read(conversation_id, user_id) do
    Repo.update_all(
      from(p in ConversationParticipant,
        where: p.conversation_id == ^conversation_id and p.user_id == ^user_id),
      set: [last_read_at: DateTime.utc_now()]
    )
  end

  @doc """
  Get a conversation by ID with participants.
  """
  def get_conversation(conversation_id) do
    Repo.get(Conversation, conversation_id)
    |> Repo.preload([participants: :user])
  end

  @doc """
  Check if a user is a participant in a conversation.
  """
  def is_participant?(conversation_id, user_id) do
    Repo.exists?(
      from p in ConversationParticipant,
        where: p.conversation_id == ^conversation_id and p.user_id == ^user_id
    )
  end

  @doc """
  Add a participant to a group conversation.
  """
  def add_participant(conversation_id, user_id, added_by_id) do
    conversation = Repo.get(Conversation, conversation_id)

    cond do
      is_nil(conversation) -> {:error, :conversation_not_found}
      conversation.type != "group" -> {:error, :not_a_group}
      not is_participant?(conversation_id, added_by_id) -> {:error, :not_authorized}
      is_participant?(conversation_id, user_id) -> {:error, :already_participant}
      true ->
        %ConversationParticipant{}
        |> ConversationParticipant.changeset(%{
          conversation_id: conversation_id,
          user_id: user_id,
          role: "member"
        })
        |> Repo.insert()
    end
  end

  @doc """
  Get the total unread message count across all conversations for a user.
  """
  def get_total_unread_count(user_id) do
    conversations = Repo.all(
      from p in ConversationParticipant,
        where: p.user_id == ^user_id,
        select: {p.conversation_id, p.last_read_at}
    )

    Enum.reduce(conversations, 0, fn {conv_id, last_read}, acc ->
      count = case last_read do
        nil ->
          Repo.aggregate(
            from(m in Message, where: m.conversation_id == ^conv_id and m.sender_id != ^user_id),
            :count
          )
        _ ->
          Repo.aggregate(
            from(m in Message,
              where: m.conversation_id == ^conv_id and
                     m.sender_id != ^user_id and
                     m.inserted_at > ^last_read),
            :count
          )
      end
      acc + count
    end)
  end





end
