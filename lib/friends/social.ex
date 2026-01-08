defmodule Friends.Social do
  @moduledoc """
  The Social context - manages rooms, photos, notes, users, and real-time interactions.
  Identity is based on browser crypto keys with social recovery.

  This module now primarily acts as a Facade, delegating specific domain logic
  to sub-modules:
  - `Friends.Social.Rooms`
  - `Friends.Social.Photos`
  - `Friends.Social.Notes`
  - `Friends.Social.Chat`
  - `Friends.Social.Relationships`
  - `Friends.WebAuthn` (delegated directly)
  """

  import Ecto.Query, warn: false
  alias Friends.Repo

  alias Friends.Social.{
    User,
    Device
  }

  # Delegate sub-modules
  alias Friends.Social.Rooms
  alias Friends.Social.Photos
  alias Friends.Social.Notes
  alias Friends.Social.Chat
  alias Friends.Social.Relationships

  # --- Admin ---
  
  def admin_username?(username) when is_binary(username) do
    admins =
      Application.get_env(:friends, :admin_usernames, [])
      |> Enum.map(&String.downcase/1)

    String.downcase(username) in admins
  end

  def admin_username?(_), do: false

  @doc """
  Check if a user struct is an admin (by username).
  """
  def is_admin?(%User{username: username}) when is_binary(username) do
    admin_username?(username)
  end
  def is_admin?(_), do: false


  # --- PubSub Wrapper ---

  def subscribe(room_code) do
    Phoenix.PubSub.subscribe(Friends.PubSub, "friends:room:#{room_code}")
  end

  def unsubscribe(room_code) do
    Phoenix.PubSub.unsubscribe(Friends.PubSub, "friends:room:#{room_code}")
  end

  def broadcast(room_code, event, payload) do
    Phoenix.PubSub.broadcast(Friends.PubSub, "friends:room:#{room_code}", {event, payload})
  end

  def broadcast(room_code, event, payload, session_id) do
    Phoenix.PubSub.broadcast(Friends.PubSub, "friends:room:#{room_code}", {event, payload, session_id})
  end

  def subscribe_to_public_feed(user_id) do
    Phoenix.PubSub.subscribe(Friends.PubSub, "friends:public_feed:#{user_id}")
  end

  # --- Rooms ---

  defdelegate get_or_create_public_square(), to: Rooms
  defdelegate get_or_create_lobby(), to: Rooms, as: :get_or_create_public_square
  defdelegate get_room_by_code(code), to: Rooms
  defdelegate get_room(id), to: Rooms
  defdelegate get_room!(id), to: Rooms
  defdelegate create_room(attrs), to: Rooms
  defdelegate generate_room_code(), to: Rooms
  defdelegate create_private_room(attrs, owner_id), to: Rooms
  defdelegate can_access_room?(room, user_id), to: Rooms
  defdelegate add_room_member(room_id, user_id, role \\ "member", invited_by_id \\ nil), to: Rooms
  defdelegate remove_room_member(room_id, user_id), to: Rooms
  defdelegate list_room_members(room_id), to: Rooms
  defdelegate list_user_private_rooms(user_id), to: Rooms
  defdelegate list_user_dashboard_rooms(user_id), to: Rooms
  defdelegate list_user_rooms(user_id), to: Rooms
  defdelegate list_user_groups(user_id), to: Rooms
  defdelegate list_user_dms(user_id), to: Rooms
  defdelegate list_user_room_ids(user_id), to: Rooms
  defdelegate list_all_rooms(limit \\ 100), to: Rooms
  defdelegate list_all_groups(limit \\ 100), to: Rooms
  defdelegate list_public_rooms(limit \\ 20), to: Rooms
  defdelegate invite_to_room(room_id, inviter_user_id, invitee_user_id), to: Rooms
  defdelegate get_room_member(room_id, user_id), to: Rooms
  defdelegate update_member_role(room_id, user_id, role), to: Rooms
  defdelegate join_room(user, room_code), to: Rooms
  defdelegate leave_room(user, room_id), to: Rooms
  defdelegate get_room_members(room_id), to: Rooms
  defdelegate create_room(user, attrs), to: Rooms # overloaded create_room
  defdelegate admin_delete_room(room_id), to: Rooms

  # --- DM Rooms ---

  defdelegate dm_room_code(user1_id, user2_id), to: Rooms
  defdelegate get_or_create_dm_room(user1_id, user2_id), to: Rooms
  defdelegate get_dm_room(user1_id, user2_id), to: Rooms
  defdelegate create_dm_room(user1_id, user2_id), to: Rooms

  # --- Photos ---

  defdelegate list_photos(room_id, limit \\ 50, opts \\ []), to: Photos
  defdelegate list_friends_photos(user_id, limit \\ 50, opts \\ []), to: Photos
  defdelegate get_photo(id), to: Photos
  defdelegate get_photo_image_data(id), to: Photos
  defdelegate create_photo(attrs, room_code), to: Photos
  defdelegate set_photo_thumbnail(photo_id, thumbnail_data, user_id, room_code), to: Photos
  defdelegate update_photo_thumbnail(photo_id, thumbnail_data, user_id), to: Photos
  defdelegate update_photo_description(photo_id, description, user_id), to: Photos
  defdelegate delete_photo(photo_id, room_code), to: Photos
  defdelegate list_user_photos(user_id, limit \\ 50, opts \\ []), to: Photos
  defdelegate list_public_photos(limit \\ 50, opts \\ []), to: Photos
  defdelegate list_photo_galleries(scope, limit \\ 50, opts \\ []), to: Photos
  defdelegate list_batch_photos(batch_id), to: Photos
  defdelegate create_public_photo(attrs, user_id), to: Photos
  defdelegate pin_photo(photo_id, room_code), to: Photos
  defdelegate unpin_photo(photo_id, room_code), to: Photos
  defdelegate delete_gallery(batch_id), to: Photos

  # --- Notes ---

  defdelegate list_notes(room_id, limit \\ 50, opts \\ []), to: Notes
  defdelegate list_friends_notes(user_id, limit \\ 50, opts \\ []), to: Notes
  defdelegate list_user_notes(user_id, limit \\ 50, opts \\ []), to: Notes
  defdelegate list_public_notes(limit \\ 50, opts \\ []), to: Notes
  defdelegate get_note(id), to: Notes
  defdelegate create_note(attrs, room_code), to: Notes
  defdelegate update_note(note_id, attrs, user_id), to: Notes
  defdelegate delete_note(note_id, user_id, room_code), to: Notes
  defdelegate admin_delete_note(note_id, room_code), to: Notes
  defdelegate create_public_note(attrs, user_id), to: Notes
  defdelegate pin_note(note_id, room_code), to: Notes
  defdelegate unpin_note(note_id, room_code), to: Notes

  # --- Friendships / Relationships ---

  defdelegate get_friend_network_ids(user_id), to: Relationships
  
  defdelegate add_trusted_friend(user_id, trusted_user_id), to: Relationships
  defdelegate confirm_trusted_friend(user_id, requester_id), to: Relationships
  defdelegate get_trusted_friend_request(user_id, trusted_user_id), to: Relationships
  defdelegate list_trusted_friends(user_id), to: Relationships
  defdelegate list_pending_trust_requests(user_id), to: Relationships
  defdelegate list_sent_trust_requests(user_id), to: Relationships
  defdelegate count_trusted_friends(user_id), to: Relationships
  defdelegate cancel_trust_request(user_id, trusted_user_id), to: Relationships
  defdelegate remove_trusted_friend(user_id, trusted_user_id), to: Relationships
  defdelegate decline_trust_request(user_id, requester_id), to: Relationships

  defdelegate add_friend(user_id, friend_user_id), to: Relationships
  defdelegate accept_friend(user_id, requester_id), to: Relationships
  defdelegate remove_friend(user_id, friend_user_id), to: Relationships
  defdelegate get_friendship(user_id, friend_user_id), to: Relationships
  defdelegate list_friends(user_id), to: Relationships
  defdelegate list_friend_requests(user_id), to: Relationships
  defdelegate list_sent_friend_requests(user_id), to: Relationships
  defdelegate count_friends(user_id), to: Relationships
  defdelegate get_connected_user_ids(user_id), to: Relationships

  @doc """
  Lists recent users who are not yet connected to the current user.
  Used for constellation graph discovery experience.
  Returns up to 100 users in random order for variety.
  """
  def list_discoverable_users(current_user_id, limit \\ 100) do
    connected_ids = Relationships.get_connected_user_ids(current_user_id)

    Repo.all(
      from u in User,
        where: u.id != ^current_user_id and u.id not in ^connected_ids,
        order_by: fragment("RANDOM()"),
        limit: ^limit,
        select: %{id: u.id, username: u.username, display_name: u.display_name, inserted_at: u.inserted_at}
    )
  end
  
  # --- Invites (Relationships) ---
  
  defdelegate validate_invite(code), to: Relationships
  defdelegate create_invite(user_id, expires_in_days \\ 7), to: Relationships
  defdelegate use_invite(invite, user), to: Relationships
  defdelegate list_user_invites(user_id), to: Relationships
  defdelegate get_invite_by_code(code), to: Relationships
  defdelegate update_invite(invite, attrs), to: Relationships
  
  # --- Recovery (Identity + Relationships) ---
  
  # request_recovery depends on User logic primarily, so implemented here or delegated?
  # Relationships.request_recovery needs checking. I didn't actually implement it fully there...
  # Wait, I wrote `nil` in the previous step and said I'll implement it here.
  # But `cast_recovery_vote` is in Relationships.
  
  def request_recovery(username) do
    case get_user_by_username(username) do
      nil ->
        {:error, :user_not_found}

      user ->
        user
        |> User.changeset(%{
          status: "recovering",
          recovery_requested_at: DateTime.utc_now()
        })
        |> Repo.update()
    end
  end

  @recovery_timeout_days 7

  @doc """
  Check if a recovery request has expired (older than 7 days).
  """
  def recovery_expired?(%{recovery_requested_at: nil}), do: false
  def recovery_expired?(%{status: status}) when status != "recovering", do: false
  def recovery_expired?(%{recovery_requested_at: requested_at}) do
    DateTime.diff(DateTime.utc_now(), requested_at, :day) > @recovery_timeout_days
  end

  @doc """
  Cancel an expired or abandoned recovery request.
  """
  def cancel_recovery(user) do
    user
    |> User.changeset(%{status: "active", recovery_requested_at: nil})
    |> Repo.update()
  end

  @doc """
  Check and auto-cancel recovery if expired, returns updated user.
  """
  def check_recovery_expiry(user) do
    if recovery_expired?(user) do
      case cancel_recovery(user) do
        {:ok, updated_user} -> {:expired, updated_user}
        _ -> {:ok, user}
      end
    else
      {:ok, user}
    end
  end

  @doc """
  Get days remaining for a recovery request.
  """
  def recovery_days_remaining(%{recovery_requested_at: nil}), do: nil
  def recovery_days_remaining(%{recovery_requested_at: requested_at}) do
    days_elapsed = DateTime.diff(DateTime.utc_now(), requested_at, :day)
    max(@recovery_timeout_days - days_elapsed, 0)
  end
  
  defdelegate cast_recovery_vote(recovering_user_id, voting_user_id, vote, new_public_key), to: Relationships
  defdelegate check_recovery_threshold(user_id, new_public_key), to: Relationships
  defdelegate get_recovery_status(user_id), to: Relationships
  defdelegate list_recovery_requests_for_voter(voter_user_id), to: Relationships
  defdelegate has_voted_for_recovery?(recovering_user_id, voter_user_id), to: Relationships
  defdelegate get_recovery_public_key(recovering_user_id), to: Relationships

  # --- Messages / Chat ---

  defdelegate list_room_messages(room_id, limit \\ 50), to: Chat
  defdelegate send_room_message(room_id, sender_id, content, type \\ "text", metadata \\ %{}, nonce \\ nil), to: Chat
  defdelegate subscribe_to_room_chat(room_id), to: Chat

  defdelegate subscribe_to_conversation(conversation_id), to: Chat
  defdelegate subscribe_to_user_conversations(user_id), to: Chat
  defdelegate get_or_create_direct_conversation(user_a_id, user_b_id), to: Chat
  defdelegate create_conversation(creator_id, participant_ids, type \\ "direct", name \\ nil), to: Chat
  defdelegate list_user_conversations(user_id), to: Chat
  defdelegate get_latest_message(conversation_id), to: Chat
  defdelegate get_unread_count(conversation_id, user_id), to: Chat
  defdelegate send_message(conversation_id, sender_id, encrypted_content, content_type, metadata \\ %{}, nonce, reply_to_id \\ nil), to: Chat
  defdelegate list_messages(conversation_id, limit \\ 50, offset \\ 0), to: Chat
  @doc """
  Mark a conversation as read. Also marks any corresponding DM room as read.
  """
  def mark_conversation_read(conversation_id, user_id) do
    user_id = if is_binary(user_id), do: String.to_integer(user_id), else: user_id
    conversation_id = if is_binary(conversation_id), do: String.to_integer(conversation_id), else: conversation_id

    # Mark conversation itself read using a slight future timestamp to clear all "now" messages
    # Chat context handles the DB call
    now_plus_buffer = DateTime.add(DateTime.utc_now(), 1, :second)
    Chat.mark_conversation_read(conversation_id, user_id, now_plus_buffer)

    # If it's a direct conversation, also mark the DM room as read
    case Chat.get_conversation(conversation_id) do
      %{type: "direct"} = conv ->
        # Find other participant
        other_participant = Enum.find(conv.participants, &(&1.user_id != user_id))
        
        if other_participant do
          # Find DM room
          case Rooms.get_dm_room(user_id, other_participant.user_id) do
            nil -> :ok
            room -> Rooms.mark_room_read(room.id, user_id, now_plus_buffer)
          end
        end
      _ -> :ok
    end
  end
  defdelegate get_conversation(conversation_id), to: Chat
  defdelegate is_participant?(conversation_id, user_id), to: Chat
  defdelegate add_participant(conversation_id, user_id, added_by_id), to: Chat
  
  @doc """
  Get the total unread count across all rooms and conversations.
  """
  def get_total_unread_count(user_id) do
    # Sum both systems
    Chat.get_total_unread_count(user_id) + Rooms.get_total_unread_count(user_id)
  end
  
  @doc """
  Mark a room as read. Also marks any linked direct conversation as read for DMs.
  """
  def mark_room_read(room_id, user_id) do
    user_id = if is_binary(user_id), do: String.to_integer(user_id), else: user_id
    room_id = if is_binary(room_id), do: String.to_integer(room_id), else: room_id

    # Mark the room itself as read using a slight future timestamp buffer
    now_plus_buffer = DateTime.add(DateTime.utc_now(), 1, :second)
    res = Rooms.mark_room_read(room_id, user_id, now_plus_buffer)

    # If it's a DM room, also find and mark the corresponding conversation as read
    room = Rooms.get_room(room_id)
    if room && room.room_type == "dm" do
      # Get members to find the other person
      members = Rooms.list_room_members(room_id)
      other_member = Enum.find(members, &(&1.user_id != user_id))
      
      if other_member do
        # Mark conversation read if it exists
        case Chat.get_or_create_direct_conversation(user_id, other_member.user_id) do
          {:ok, conv} -> Chat.mark_conversation_read(conv.id, user_id, now_plus_buffer)
          _ -> :ok
        end
      end
    end
    
    res
  end

  @doc """
  Get the single latest unread message from either Conversations OR Rooms.
  """
  def get_latest_unread_message(user_id) do
    chat_msg = Chat.get_latest_unread_message(user_id)
    room_msg = Rooms.get_latest_unread_message(user_id)

    case {chat_msg, room_msg} do
      {nil, nil} -> nil
      {msg, nil} -> msg
      {nil, msg} -> msg
      {c_msg, r_msg} ->
        if DateTime.compare(c_msg.inserted_at, r_msg.inserted_at) == :gt do
          c_msg
        else
          r_msg
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
            master_id: (existing && existing.master_id) || Ecto.UUID.generate()
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

  def link_device_to_user(browser_id, user_id) do
    case get_device_by_browser(browser_id) do
      nil ->
        {:error, :device_not_found}

      device ->
        device
        |> Device.changeset(%{user_id: user_id})
        |> Repo.update()
    end
  end

  # --- Users (Identity) ---

  # alias Friends.Social.TrustedFriend

  def register_user(attrs) do
    invite_code = attrs[:invite_code] || attrs["invite_code"]
    referrer = attrs[:referrer] || attrs["referrer"]
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

      referrer && referrer != "" ->
        # New simplified referral: username-based, creates regular friendship
        referrer_username = String.trim(referrer) |> String.downcase() |> String.replace_prefix("@", "")
        
        case Repo.get_by(User, username: referrer_username) do
          nil ->
            # Referrer not found - still allow registration
            create_user(attrs, %{created_by_id: nil})

          referrer_user ->
            # Create user and establish friendship with referrer
            with {:ok, user} <- create_user(attrs, %{created_by_id: referrer_user.id}) do
              # Create mutual friendship (not trusted - regular friends)
              Relationships.create_mutual_friendship(referrer_user.id, user.id)
              {:ok, user}
            end
        end

      invite_code && invite_code != "" ->
        # Legacy invite code path - creates mutual trust with inviter
        with {:ok, invite} <- Relationships.validate_invite(invite_code),
             {:ok, user} <- create_user(attrs, invite) do
          # Mark invite as used (skip for admin invite which has no ID)
          if invite.id, do: Relationships.use_invite(invite, user)
          # Create mutual trust between inviter and invitee
          if invite.created_by_id do
            Relationships.create_mutual_trust(invite.created_by_id, user.id)
          end

          {:ok, user}
        end

      true ->
        # Open registration without invite code
        create_user(attrs, %{created_by_id: nil})
    end
  end

  defp create_user(attrs, invite) do
    case %User{}
         |> User.changeset(Map.put(attrs, :invited_by_id, invite.created_by_id))
         |> Repo.insert() do
      {:ok, user} ->
        # Broadcast new user for constellation real-time updates
        broadcast_new_user(user)
        {:ok, user}

      error ->
        error
    end
  end

  defp broadcast_new_user(user) do
    # Invalidate welcome graph cache so new user appears
    Friends.GraphCache.invalidate_welcome()
    
    Phoenix.PubSub.broadcast(
      Friends.PubSub,
      "friends:global",
      {:welcome_new_user, %{
        id: user.id,
        username: user.username,
        display_name: user.display_name || user.username,
        inserted_at: user.inserted_at,
        # Use thumbnail for graph display if available
        avatar_url: user.avatar_url_thumb || user.avatar_url
      }}
    )
  end

  def get_user_by_public_key(public_key) when is_map(public_key) do
    # Compare the key components (x, y coordinates for ECDSA)
    Repo.one(
      from u in User,
        where:
          fragment(
            "?->>'x' = ? AND ?->>'y' = ?",
            u.public_key,
            ^public_key["x"],
            u.public_key,
            ^public_key["y"]
          ),
        limit: 1
    )
  end

  def get_user_by_public_key(_), do: nil

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

  def update_user_avatar(user_id, avatar_url, thumb_url \\ nil) do
    user = get_user(user_id)
    if user do
      attrs = %{avatar_url: avatar_url}
      attrs = if thumb_url, do: Map.put(attrs, :avatar_url_thumb, thumb_url), else: attrs
      
      user
      |> User.changeset(attrs)
      |> Repo.update()
    else
      {:error, :user_not_found}
    end
  end

  @doc """
  Update user's avatar corner position preference.
  Valid positions: "top-left", "top-right", "bottom-left", "bottom-right"
  """
  def update_avatar_position(user_id, position) do
    user = get_user(user_id)
    if user do
      user
      |> User.changeset(%{avatar_position: position})
      |> Repo.update()
    else
      {:error, :user_not_found}
    end
  end

  @doc """
  Admin: delete a user and all their content.
  This deletes: photos, notes, room memberships, friendships, devices, etc.
  """
  def admin_delete_user(user_id) when is_integer(user_id) do
    case get_user(user_id) do
      nil ->
        {:error, :not_found}

      user ->
        # Delete user's photos (public feed ones - room photos will cascade with room membership)
        Repo.delete_all(from p in Friends.Social.Photo, where: p.user_id == ^"user-#{user_id}")
        
        # Delete user's notes
        Repo.delete_all(from n in Friends.Social.Note, where: n.user_id == ^"user-#{user_id}")
        
        # Delete friendships
        Repo.delete_all(from f in Friends.Social.Friendship, where: f.user_id == ^user_id or f.friend_user_id == ^user_id)
        
        # Delete trusted friend relationships
        Repo.delete_all(from tf in Friends.Social.TrustedFriend, where: tf.user_id == ^user_id or tf.trusted_user_id == ^user_id)
        
        # Delete room memberships
        Repo.delete_all(from rm in Friends.Social.RoomMember, where: rm.user_id == ^user_id)
        
        # Delete devices
        Repo.delete_all(from d in Friends.Social.Device, where: d.user_id == ^user_id)
        
        # Delete the user
        case Repo.delete(user) do
          {:ok, deleted} ->
            # Broadcast user removal for real-time graph updates
            Phoenix.PubSub.broadcast(Friends.PubSub, "friends:global", {:user_removed, user_id})
            Phoenix.PubSub.broadcast(Friends.PubSub, "friends:user:#{user_id}", {:user_removed, user_id})
            
            {:ok, deleted}
          error -> error
        end
    end
  end

  def admin_delete_user(user_id) when is_binary(user_id) do
    case Integer.parse(user_id) do
      {id, ""} -> admin_delete_user(id)
      _ -> {:error, :invalid_id}
    end
  end

  def search_users(query, current_user_id) when is_binary(query) and is_integer(current_user_id) and byte_size(query) >= 2 do
    pattern = "%#{query}%"

    Repo.all(
      from u in User,
        where:
          u.id != ^current_user_id and
            (ilike(u.username, ^pattern) or ilike(u.display_name, ^pattern)),
        order_by: [asc: u.username],
        limit: 20
    )
  end

  @doc """
  Search users by username or display name with keyword options.
  Used by omnibox search.
  """
  def search_users(query, opts) when is_binary(query) and is_list(opts) do
    limit = Keyword.get(opts, :limit, 20)
    pattern = "%#{String.trim(query)}%"

    if byte_size(String.trim(query)) >= 1 do
      Repo.all(
        from u in User,
          where: ilike(u.username, ^pattern) or ilike(u.display_name, ^pattern),
          order_by: [asc: u.username],
          limit: ^limit
      )
    else
      []
    end
  end

  def search_users(_, _), do: []

  @doc """
  Search user's groups by name.
  """
  def search_user_groups(user_id, query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    pattern = "%#{String.trim(query)}%"
    
    if byte_size(String.trim(query)) >= 1 do
      Rooms.search_user_groups(user_id, pattern, limit)
    else
      []
    end
  end

  @doc """
  Search among user's existing friends/contacts.
  Used when adding members to rooms (only from contacts, not all users).
  """
  def search_friends(user_id, query) when is_binary(query) and byte_size(query) >= 2 do
    pattern = "%#{query}%"
    friend_ids = Relationships.get_contact_user_ids(user_id)
    
    # Convert string user_ids to integers
    int_friend_ids = friend_ids
      |> Enum.map(fn id ->
        case id do
          "user-" <> n -> String.to_integer(n)
          n when is_integer(n) -> n
          n when is_binary(n) -> String.to_integer(n)
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    Repo.all(
      from u in User,
        where: u.id in ^int_friend_ids and
          (ilike(u.username, ^pattern) or ilike(u.display_name, ^pattern)),
        order_by: [asc: u.username],
        limit: 20
    )
  end

  def search_friends(_, _), do: []

  def get_user_by_username(username) do
    Repo.get_by(User, username: String.downcase(username))
  end

  def username_available?(username) do
    normalized = String.downcase(username)
    not Repo.exists?(from u in User, where: u.username == ^normalized)
  end
  
  # --- Moderation (Block/Report) ---

  alias Friends.Social.Report
  alias Friends.Social.Block

  def report_user(reporter_id, reported_id, reason \\ "Abusive behavior") do
    %Report{}
    |> Report.changeset(%{
      reporter_id: reporter_id,
      reported_id: reported_id,
      reason: reason,
      status: "pending"
    })
    |> Repo.insert()
  end

  def block_user(blocker_id, blocked_id) do
    # 1. Create block record
    block_result = %Block{}
    |> Block.changeset(%{blocker_id: blocker_id, blocked_id: blocked_id})
    |> Repo.insert()

    # 2. Side effects: Remove friendship if exists
    Relationships.remove_friend(blocker_id, blocked_id)
    # Remove from trusted?
    Relationships.remove_trusted_friend(blocker_id, blocked_id)
    
    block_result
  end

  def is_blocked?(user_id, target_id) do
    # Check if user_id has blocked target_id OR target_id has blocked user_id
    query = from b in Block,
      where: (b.blocker_id == ^user_id and b.blocked_id == ^target_id) or
             (b.blocker_id == ^target_id and b.blocked_id == ^user_id)
    
    Repo.exists?(query)
  end

  
  def generate_auth_challenge do
    :crypto.strong_rand_bytes(32) |> Base.encode64()
  end

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
            Logger.info(
              "Public key decoded successfully: x=#{byte_size(x)} bytes, y=#{byte_size(y)} bytes"
            )

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

            Logger.info(
              "About to call crypto.verify with challenge length: #{String.length(challenge)}, signature size: #{byte_size(der_signature)}"
            )

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
  
  # --- User Devices (Device Attestation) ---

  alias Friends.Social.UserDevice

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

  def list_user_devices(user_id) do
    Repo.all(
      from d in UserDevice,
        where: d.user_id == ^user_id and d.revoked == false,
        order_by: [desc: d.last_seen_at]
    )
  end

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

  def count_trusted_devices(user_id) do
    Repo.one(
      from d in UserDevice,
        where: d.user_id == ^user_id and d.trusted == true and d.revoked == false,
        select: count(d.id)
    )
  end

  # --- WebAuthn ---

  defdelegate generate_webauthn_registration_challenge(user),
    to: Friends.WebAuthn,
    as: :generate_registration_challenge

  defdelegate generate_webauthn_authentication_challenge(user),
    to: Friends.WebAuthn,
    as: :generate_authentication_challenge

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

  def verify_webauthn_assertion(user_id, assertion_data, challenge) do
    assertion_response = %{
      "clientDataJSON" => assertion_data["response"]["clientDataJSON"],
      "authenticatorData" => assertion_data["response"]["authenticatorData"],
      "signature" => assertion_data["response"]["signature"],
      "id" => assertion_data["rawId"]
    }

    Friends.WebAuthn.verify_authentication(assertion_response, challenge, user_id)
  end

  defdelegate list_webauthn_credentials(user_id), to: Friends.WebAuthn, as: :list_credentials

  def delete_webauthn_credential(user_id, credential_id) do
    Friends.WebAuthn.delete_credential(user_id, credential_id)
  end

  defdelegate has_webauthn_credentials?(user_id), to: Friends.WebAuthn, as: :has_credentials?

  @doc """
  Atomically register a user WITH their WebAuthn credential.
  Uses Ecto.Multi to ensure both user and credential are created together,
  or neither is created if WebAuthn verification fails.
  
  This prevents orphaned users when WebAuthn fails.
  """
  def register_user_with_webauthn(attrs, credential_data, challenge) do
    alias Ecto.Multi
    
    Multi.new()
    |> Multi.run(:user, fn _repo, _changes ->
      # Create the user first
      register_user(attrs)
    end)
    |> Multi.run(:webauthn_verify, fn _repo, %{user: user} ->
      # Verify the WebAuthn credential (doesn't store yet)
      attestation_response = %{
        "clientDataJSON" => credential_data["response"]["clientDataJSON"],
        "attestationObject" => credential_data["response"]["attestationObject"],
        "id" => credential_data["rawId"],
        "transports" => credential_data["transports"] || []
      }
      
      case Friends.WebAuthn.verify_registration(attestation_response, challenge, user.id) do
        {:ok, cred_data} -> {:ok, cred_data}
        {:error, reason} -> {:error, {:webauthn_failed, reason}}
      end
    end)
    |> Multi.run(:credential, fn _repo, %{webauthn_verify: cred_data} ->
      # Store the verified credential
      Friends.WebAuthn.store_credential(cred_data, nil)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user, credential: _credential}} ->
        {:ok, user}
        
      {:error, :user, %Ecto.Changeset{} = changeset, _changes} ->
        {:error, changeset}
        
      {:error, :user, :invalid_invite, _changes} ->
        {:error, :invalid_invite}
        
      {:error, :webauthn_verify, {:webauthn_failed, reason}, _changes} ->
        {:error, {:webauthn, reason}}
        
      {:error, :credential, reason, _changes} ->
        {:error, {:credential_storage, reason}}
        
      {:error, step, reason, _changes} ->
        {:error, {step, reason}}
    end
  end
  
  # --- Public Feed Aggregator ---
  
  # This combines photos and notes. It crosses domains, so it fits well in the Facade/Aggregator.
  
  def list_public_feed_items(user_id, limit \\ 50, opts \\ []) do
    offset_val = Keyword.get(opts, :offset, 0)
    contact_ids = Relationships.get_contact_user_ids(user_id)

    # Include own posts in the feed
    all_user_ids = [if(is_integer(user_id), do: "user-#{user_id}", else: user_id) | contact_ids]

    # Fetch photos from contacts + self
    # fetch more than limit because grouping will reduce count
    fetch_limit = limit * 3 
    
    photos =
      Repo.all(
        from p in Friends.Social.Photo,
          where: p.user_id in ^all_user_ids and is_nil(p.room_id),
          order_by: [desc: p.uploaded_at],
          limit: ^fetch_limit,
          offset: ^offset_val,
          select: %{
            id: p.id,
            type: :photo,
            user_id: p.user_id,
            user_color: p.user_color,
            user_name: p.user_name,
            thumbnail_data: p.thumbnail_data,
            description: p.description,
            uploaded_at: p.uploaded_at,
            content_type: p.content_type,
            batch_id: p.batch_id,
            image_data:
              fragment(
                "CASE WHEN ? = 'audio/encrypted' THEN ? ELSE NULL END",
                p.content_type,
                p.image_data
              )
          }
      )

    # Group photos into galleries
    {galleries, singles} = group_photos_into_galleries(photos)
    photo_items = singles ++ galleries

    # Fetch notes from contacts + self
    notes =
      Repo.all(
        from n in Friends.Social.Note,
          where: n.user_id in ^all_user_ids and is_nil(n.room_id),
          order_by: [desc: n.inserted_at],
          limit: ^limit,
          offset: ^offset_val,
          select: %{
            id: n.id,
            type: :note,
            user_id: n.user_id,
            user_color: n.user_color,
            user_name: n.user_name,
            content: n.content,
            inserted_at: n.inserted_at
          }
      )

    # Combine and sort by inserted_at, newest first (handle mixed DateTime/NaiveDateTime)
    (photo_items ++ notes)
    |> Enum.sort_by(
      fn item ->
        timestamp = Map.get(item, :uploaded_at) || Map.get(item, :inserted_at)
        
        case timestamp do
          %DateTime{} = dt -> DateTime.to_unix(dt)
          %NaiveDateTime{} = ndt -> NaiveDateTime.diff(ndt, ~N[1970-01-01 00:00:00])
          _ -> 0
        end
      end,
      :desc
    )
    |> Enum.take(limit)
  end

  @doc """
  Admin feed: returns ALL public photos and notes system-wide (no contact filtering).
  """
  def list_admin_feed_items(limit \\ 50, opts \\ []) do
    offset_val = Keyword.get(opts, :offset, 0)
    fetch_limit = limit * 3

    # All public photos (no room_id = public feed)
    photos =
      Repo.all(
        from p in Friends.Social.Photo,
          where: is_nil(p.room_id),
          order_by: [desc: p.uploaded_at],
          limit: ^fetch_limit,
          offset: ^offset_val,
          select: %{
            id: p.id,
            type: :photo,
            user_id: p.user_id,
            user_color: p.user_color,
            user_name: p.user_name,
            thumbnail_data: p.thumbnail_data,
            description: p.description,
            uploaded_at: p.uploaded_at,
            content_type: p.content_type,
            batch_id: p.batch_id,
            image_data:
              fragment(
                "CASE WHEN ? = 'audio/encrypted' THEN ? ELSE NULL END",
                p.content_type,
                p.image_data
              )
          }
      )

    {galleries, singles} = group_photos_into_galleries(photos)
    photo_items = singles ++ galleries

    # All public notes (no room_id = public feed)
    notes =
      Repo.all(
        from n in Friends.Social.Note,
          where: is_nil(n.room_id),
          order_by: [desc: n.inserted_at],
          limit: ^limit,
          offset: ^offset_val,
          select: %{
            id: n.id,
            type: :note,
            user_id: n.user_id,
            user_color: n.user_color,
            user_name: n.user_name,
            content: n.content,
            inserted_at: n.inserted_at
          }
      )

    (photo_items ++ notes)
    |> Enum.sort_by(
      fn item ->
        timestamp = Map.get(item, :uploaded_at) || Map.get(item, :inserted_at)
        case timestamp do
          %DateTime{} = dt -> DateTime.to_unix(dt)
          %NaiveDateTime{} = ndt -> NaiveDateTime.diff(ndt, ~N[1970-01-01 00:00:00])
          _ -> 0
        end
      end,
      :desc
    )
    |> Enum.take(limit)
  end

  def group_photos_into_galleries(photos) do
    {batched, singles} = Enum.split_with(photos, & &1.batch_id)

    galleries =
      batched
      |> Enum.group_by(& &1.batch_id)
      |> Enum.map(fn {batch_id, batch_photos} ->
        first_photo = List.first(batch_photos)
        %{
          type: :gallery,
          batch_id: batch_id,
          photo_count: length(batch_photos),
          first_photo: first_photo,
          all_photos: batch_photos,
          user_id: first_photo.user_id,
          user_color: first_photo.user_color,
          user_name: first_photo.user_name,
          uploaded_at: first_photo.uploaded_at,
          id: "gallery-#{batch_id}",
          unique_id: "gallery-#{batch_id}"
        }
      end)
    
    {galleries, singles}
  end


  # --- Helper for Relationships broadcast (if needed, but implemented in Relationships now) ---
  
  defdelegate broadcast_to_contacts(user_id, event, payload), to: Relationships
  
  # --- Helper for user id string ---
  
  # Was private in social.ex, but used by `list_public_feed_items` logic implicitly or explicitly?
  # The aggregator above re-implemented the logic inline.
  # So we don't need to expose it.
end
