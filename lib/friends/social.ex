defmodule Friends.Social do
  @moduledoc """
  The Social context - manages rooms, photos, notes, users, and real-time interactions.
  Identity is based on browser crypto keys with social recovery.
  """

  import Ecto.Query, warn: false
  alias Friends.Repo
  alias Friends.Social.{Room, Photo, Note, Device, Presence, User, Invite, TrustedFriend, RecoveryVote, RoomMember}

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

  def get_or_create_lobby do
    case Repo.get_by(Room, code: "lobby") do
      nil ->
        {:ok, room} = create_room(%{code: "lobby", name: "Lobby"})
        room

      room ->
        room
    end
  end

  def get_room_by_code(code) do
    Repo.get_by(Room, code: code)
  end

  def get_room(id), do: Repo.get(Room, id)

  def create_room(attrs) do
    %Room{}
    |> Room.changeset(attrs)
    |> Repo.insert()
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
    Repo.transaction(fn ->
      room_attrs = Map.merge(attrs, %{is_private: true, owner_id: owner_id})
      
      case create_room(room_attrs) do
        {:ok, room} ->
          # Add owner as member
          {:ok, _member} = add_room_member(room.id, owner_id, "owner")
          room
        
        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
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
    %RoomMember{}
    |> RoomMember.changeset(%{
      room_id: room_id,
      user_id: user_id,
      role: role,
      invited_by_id: invited_by_id
    })
    |> Repo.insert()
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

  # --- Photos ---

  def list_photos(room_id, limit \\ 50) do
    Photo
    |> where([p], p.room_id == ^room_id)
    |> order_by([p], desc: p.uploaded_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  List photos from a user's friend network (trusted friends + people who trust them)
  """
  def list_friends_photos(user_id, limit \\ 50) do
    friend_user_ids = get_friend_network_ids(user_id)
    
    Photo
    |> where([p], p.user_id in ^friend_user_ids)
    |> order_by([p], desc: p.uploaded_at)
    |> limit(^limit)
    |> Repo.all()
  end

  def get_photo(id), do: Repo.get(Photo, id)

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

  def set_photo_thumbnail(photo_id, thumbnail_data, user_id)
      when is_integer(photo_id) and is_binary(thumbnail_data) do
    Photo
    |> where([p], p.id == ^photo_id and p.user_id == ^user_id)
    |> Repo.update_all(set: [thumbnail_data: thumbnail_data])
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

  def list_notes(room_id, limit \\ 50) do
    Note
    |> where([n], n.room_id == ^room_id)
    |> order_by([n], desc: n.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  List notes from a user's friend network
  """
  def list_friends_notes(user_id, limit \\ 50) do
    friend_user_ids = get_friend_network_ids(user_id)
    
    Note
    |> where([n], n.user_id in ^friend_user_ids)
    |> order_by([n], desc: n.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Get the user IDs in someone's friend network.
  This includes:
  - Their confirmed trusted friends
  - People who have confirmed them as a trusted friend
  - Themselves
  """
  def get_friend_network_ids(user_id) do
    # Get friends I trust
    my_friends = Repo.all(
      from tf in TrustedFriend,
        where: tf.user_id == ^user_id and tf.status == "confirmed",
        select: tf.trusted_user_id
    )
    
    # Get people who trust me
    trusted_by = Repo.all(
      from tf in TrustedFriend,
        where: tf.trusted_user_id == ^user_id and tf.status == "confirmed",
        select: tf.user_id
    )
    
    # Combine and add self, converting to string user_ids
    friend_ids = (my_friends ++ trusted_by ++ [user_id])
    |> Enum.uniq()
    |> Enum.map(&"user-#{&1}")
    
    friend_ids
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
        if note.user_id == user_id do
          note
          |> Note.changeset(attrs)
          |> Repo.update()
        else
          {:error, :unauthorized}
        end
    end
  end

  def delete_note(note_id, user_id, room_code) do
    case Repo.get(Note, note_id) do
      nil ->
        {:error, :not_found}

      note ->
        if note.user_id == user_id do
          case Repo.delete(note) do
            {:ok, _} ->
              broadcast(room_code, :note_deleted, %{id: note_id})
              {:ok, note}

            error ->
              error
          end
        else
          {:error, :unauthorized}
        end
    end
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
  Requires a valid invite code.
  """
  def register_user(attrs) do
    invite_code = attrs[:invite_code] || attrs["invite_code"]
    
    with {:ok, invite} <- validate_invite(invite_code),
         {:ok, user} <- create_user(attrs, invite) do
      # Mark invite as used
      use_invite(invite, user)
      {:ok, user}
    end
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
    try do
      # Decode the signature from base64
      {:ok, signature_bin} = Base.decode64(signature_base64)

      # The public key is in JWK format (base64url x/y)
      {:ok, x} = Base.url_decode64(public_key["x"], padding: false)
      {:ok, y} = Base.url_decode64(public_key["y"], padding: false)

      # Create the EC public key point (uncompressed format: 04 || x || y)
      public_key_point = <<4>> <> x <> y

      # Create the EC key structure for Erlang crypto
      ec_key = {:ECPoint, public_key_point, {:namedCurve, :secp256r1}}

      # WebCrypto ECDSA may return raw (r||s) 64 bytes or DER. Handle both.
      der_signature =
        case byte_size(signature_bin) do
          64 ->
            <<r::binary-size(32), s::binary-size(32)>> = signature_bin
            encode_der_signature(r, s)

          _ ->
            signature_bin
        end

      :crypto.verify(:ecdsa, :sha256, challenge, der_signature, [ec_key])
    rescue
      _ -> false
    catch
      _, _ -> false
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
  Get user by ID
  """
  def get_user(id), do: Repo.get(User, id)

  @doc """
  Check if username is available
  """
  def username_available?(username) do
    normalized = String.downcase(username)
    not Repo.exists?(from u in User, where: u.username == ^normalized)
  end

  @doc """
  Search users by username (for adding trusted friends)
  """
  def search_users(query, exclude_user_id \\ nil) do
    query = String.downcase(query) <> "%"
    
    User
    |> where([u], ilike(u.username, ^query))
    |> where([u], u.status == "active")
    |> maybe_exclude_user(exclude_user_id)
    |> limit(10)
    |> Repo.all()
  end

  defp maybe_exclude_user(query, nil), do: query
  defp maybe_exclude_user(query, user_id) do
    where(query, [u], u.id != ^user_id)
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
        tf
        |> TrustedFriend.changeset(%{
          status: "confirmed",
          confirmed_at: DateTime.utc_now()
        })
        |> Repo.update()
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
  Count confirmed trusted friends
  """
  def count_trusted_friends(user_id) do
    Repo.one(
      from tf in TrustedFriend,
        where: tf.user_id == ^user_id and tf.status == "confirmed",
        select: count(tf.id)
    )
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
  Cast recovery vote
  """
  def cast_recovery_vote(recovering_user_id, voting_user_id, vote, new_public_key) do
    # Verify voter is a trusted friend
    case get_trusted_friend_request(recovering_user_id, voting_user_id) do
      nil -> {:error, :not_trusted_friend}
      tf when tf.status != "confirmed" -> {:error, :not_confirmed_friend}
      _tf ->
        %RecoveryVote{}
        |> RecoveryVote.changeset(%{
          recovering_user_id: recovering_user_id,
          voting_user_id: voting_user_id,
          vote: vote,
          new_public_key: new_public_key
        })
        |> Repo.insert()
        |> case do
          {:ok, vote} -> check_recovery_threshold(recovering_user_id, new_public_key)
          error -> error
        end
    end
  end

  @doc """
  Check if recovery threshold is met (4 out of 5)
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
      # Recovery successful - update public key
      case get_user(user_id) do
        nil -> {:error, :user_not_found}
        user ->
          user
          |> User.changeset(%{
            public_key: new_public_key,
            status: "active",
            recovery_requested_at: nil
          })
          |> Repo.update()
          |> case do
            {:ok, user} ->
              # Clean up recovery votes
              Repo.delete_all(from rv in RecoveryVote, where: rv.recovering_user_id == ^user_id)
              {:ok, :recovered, user}
            error -> error
          end
      end
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
end

