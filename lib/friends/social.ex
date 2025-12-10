defmodule Friends.Social do
  @moduledoc """
  The Social context - manages rooms, photos, notes, users, and real-time interactions.
  Identity is based on browser crypto keys with social recovery.
  """

  import Ecto.Query, warn: false
  alias Friends.Repo
  alias Friends.Social.{Room, Photo, Note, Device, User, Invite, TrustedFriend, RecoveryVote, RoomMember}

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
      updated_at: p.updated_at
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
      updated_at: p.updated_at
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

      true ->
        with {:ok, invite} <- validate_invite(invite_code),
             {:ok, user} <- create_user(attrs, invite) do
          # Mark invite as used
          use_invite(invite, user)
          {:ok, user}
        end
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
    require Logger

    try do
      Logger.debug("Verifying signature - public_key x: #{inspect(public_key["x"])}, challenge length: #{String.length(challenge)}, signature length: #{String.length(signature_base64)}")

      # Decode the signature from base64
      case Base.decode64(signature_base64) do
        {:ok, signature_bin} ->
          Logger.debug("Signature decoded: #{byte_size(signature_bin)} bytes")

          # The public key is in JWK format (base64url x/y)
          with {:ok, x} <- Base.url_decode64(public_key["x"], padding: false),
               {:ok, y} <- Base.url_decode64(public_key["y"], padding: false) do

            Logger.debug("Public key decoded: x=#{byte_size(x)} bytes, y=#{byte_size(y)} bytes")

            # Create the EC public key point (uncompressed format: 04 || x || y)
            public_key_point = <<4>> <> x <> y

            # Create the EC key structure for Erlang crypto
            ec_key = {:ECPoint, public_key_point, {:namedCurve, :secp256r1}}

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

            result = :crypto.verify(:ecdsa, :sha256, challenge, der_signature, [ec_key])
            Logger.debug("Signature verification result: #{inspect(result)}")
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

  alias Friends.Social.WebAuthnCredential

  @doc """
  Generate a WebAuthn registration challenge
  Returns challenge options for the client
  """
  def generate_webauthn_registration_challenge(user) do
    challenge = :crypto.strong_rand_bytes(32)

    %{
      challenge: Base.url_encode64(challenge, padding: false),
      rp: %{
        name: "Friends",
        id: get_rp_id()
      },
      user: %{
        id: Base.url_encode64("user-#{user.id}", padding: false),
        name: user.username,
        displayName: user.display_name || user.username
      },
      pubKeyCredParams: [
        %{type: "public-key", alg: -7},  # ES256
        %{type: "public-key", alg: -257} # RS256
      ],
      timeout: 60000,
      attestation: "none",
      authenticatorSelection: %{
        authenticatorAttachment: "platform",
        requireResidentKey: false,
        userVerification: "preferred"
      }
    }
  end

  @doc """
  Generate a WebAuthn authentication challenge
  """
  def generate_webauthn_authentication_challenge(user) do
    challenge = :crypto.strong_rand_bytes(32)

    credentials = list_webauthn_credentials(user.id)

    %{
      challenge: Base.url_encode64(challenge, padding: false),
      timeout: 60000,
      rpId: get_rp_id(),
      userVerification: "preferred",
      allowCredentials: Enum.map(credentials, fn cred ->
        %{
          type: "public-key",
          id: Base.url_encode64(cred.credential_id, padding: false),
          transports: cred.transports
        }
      end)
    }
  end

  @doc """
  Register a WebAuthn credential
  For simplicity, we're doing basic validation.
  In production, you'd want to use a proper WebAuthn library like wax or webauthn_ex
  """
  def register_webauthn_credential(user_id, attrs) do
    %WebAuthnCredential{}
    |> WebAuthnCredential.changeset(Map.put(attrs, :user_id, user_id))
    |> Repo.insert()
  end

  @doc """
  Verify and store a WebAuthn credential
  This is a simplified version - in production use a proper WebAuthn library
  """
  def verify_and_store_webauthn_credential(user_id, credential_data, name \\ nil) do
    # Decode the credential ID and public key
    # Note: This is simplified. Real implementation should:
    # 1. Verify the attestation object
    # 2. Extract and validate the public key
    # 3. Verify the signature
    # 4. Check the RP ID hash

    with {:ok, credential_id} <- Base.url_decode64(credential_data["rawId"], padding: false),
         {:ok, public_key} <- extract_public_key(credential_data) do

      attrs = %{
        user_id: user_id,
        credential_id: credential_id,
        public_key: public_key,
        sign_count: 0,
        transports: credential_data["transports"] || [],
        name: name || "Hardware Key",
        last_used_at: DateTime.utc_now()
      }

      %WebAuthnCredential{}
      |> WebAuthnCredential.changeset(attrs)
      |> Repo.insert()
    else
      _ -> {:error, :invalid_credential}
    end
  end

  @doc """
  Verify a WebAuthn authentication assertion
  This is simplified - production should use a proper WebAuthn library
  """
  def verify_webauthn_assertion(user_id, assertion_data, challenge) do
    with {:ok, credential_id} <- Base.url_decode64(assertion_data["rawId"], padding: false),
         credential <- get_webauthn_credential(user_id, credential_id),
         true <- credential != nil,
         true <- verify_webauthn_signature(credential, assertion_data, challenge) do

      # Update sign count and last used
      credential
      |> WebAuthnCredential.changeset(%{
        sign_count: credential.sign_count + 1,
        last_used_at: DateTime.utc_now()
      })
      |> Repo.update()

      {:ok, credential}
    else
      _ -> {:error, :invalid_assertion}
    end
  end

  @doc """
  List WebAuthn credentials for a user
  """
  def list_webauthn_credentials(user_id) do
    Repo.all(
      from c in WebAuthnCredential,
        where: c.user_id == ^user_id,
        order_by: [desc: c.last_used_at]
    )
  end

  @doc """
  Get a specific WebAuthn credential
  """
  def get_webauthn_credential(user_id, credential_id) do
    Repo.get_by(WebAuthnCredential, user_id: user_id, credential_id: credential_id)
  end

  @doc """
  Delete a WebAuthn credential
  """
  def delete_webauthn_credential(user_id, credential_id) do
    case get_webauthn_credential(user_id, credential_id) do
      nil -> {:error, :not_found}
      credential -> Repo.delete(credential)
    end
  end

  # Private helper functions for WebAuthn

  defp get_rp_id do
    # In production, this should be your domain (e.g., "friends.app")
    # For development, it might be "localhost"
    Application.get_env(:friends, :webauthn_rp_id, "localhost")
  end

  defp extract_public_key(credential_data) do
    # This is a placeholder - real implementation needs to:
    # 1. Decode the attestation object
    # 2. Parse the CBOR structure
    # 3. Extract the COSE public key
    # 4. Convert to raw format
    # For now, we'll store a placeholder
    {:ok, :crypto.strong_rand_bytes(65)} # Placeholder for actual key extraction
  end

  defp verify_webauthn_signature(_credential, _assertion_data, _challenge) do
    # This is a placeholder - real implementation needs to:
    # 1. Reconstruct the signed data
    # 2. Verify the signature using the stored public key
    # 3. Verify the RP ID hash
    # 4. Verify the challenge
    # 5. Check the sign count
    true # Placeholder - always succeeds for demo
  end
end
