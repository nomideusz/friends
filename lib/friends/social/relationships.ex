defmodule Friends.Social.Relationships do
  @moduledoc """
  Manages Relationships (Friendships, Trusted Friends, Invites).
  """
  import Ecto.Query, warn: false
  alias Friends.Repo
  alias Friends.Social.{Friendship, TrustedFriend, Invite, User, RecoveryVote}
  alias Friends.Social.Rooms

  # --- Trusted Friends ---

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

  def confirm_trusted_friend(user_id, requester_id) do
    case get_trusted_friend_request(requester_id, user_id) do
      nil ->
        {:error, :not_found}

      tf ->
        # Confirm the incoming request
        result =
          tf
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

          error ->
            error
        end
    end
  end

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

  def get_trusted_friend_request(user_id, trusted_user_id) do
    Repo.get_by(TrustedFriend, user_id: user_id, trusted_user_id: trusted_user_id)
  end

  def list_trusted_friends(user_id) do
    Repo.all(
      from tf in TrustedFriend,
        where: tf.user_id == ^user_id and tf.status == "confirmed",
        preload: [:trusted_user]
    )
  end

  def list_pending_trust_requests(user_id) do
    Repo.all(
      from tf in TrustedFriend,
        where: tf.trusted_user_id == ^user_id and tf.status == "pending",
        preload: [:user]
    )
  end

  def list_sent_trust_requests(user_id) do
    Repo.all(
      from tf in TrustedFriend,
        where: tf.user_id == ^user_id and tf.status == "pending",
        preload: [:trusted_user]
    )
  end

  def count_trusted_friends(user_id) do
    Repo.one(
      from tf in TrustedFriend,
        where: tf.user_id == ^user_id and tf.status == "confirmed",
        select: count(tf.id)
    )
  end

  # --- Friendships (Social Connections) ---

  def add_friend(user_id, friend_user_id) do
    if user_id == friend_user_id do
      {:error, :cannot_friend_self}
    else
      # Check if friendship already exists (in either direction)
      existing =
        get_friendship(user_id, friend_user_id) || get_friendship(friend_user_id, user_id)

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

  def accept_friend(user_id, requester_id) do
    case get_friendship(requester_id, user_id) do
      nil ->
        {:error, :no_pending_request}

      %{status: "pending"} = friendship ->
        result =
          friendship
          |> Friendship.changeset(%{
            status: "accepted",
            accepted_at: DateTime.utc_now()
          })
          |> Repo.update()

        # Auto-create DM room for the new friends
        case result do
          {:ok, _} ->
            Rooms.get_or_create_dm_room(user_id, requester_id)

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

  def remove_friend(user_id, friend_user_id) do
    # Check both directions
    friendship =
      get_friendship(user_id, friend_user_id) || get_friendship(friend_user_id, user_id)

    case friendship do
      nil ->
        {:error, :not_friends}

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

  def get_friendship(user_id, friend_user_id) do
    Repo.get_by(Friendship, user_id: user_id, friend_user_id: friend_user_id)
  end

  def list_friends(user_id) do
    # Friends I added
    my_friends =
      Repo.all(
        from f in Friendship,
          where: f.user_id == ^user_id and f.status == "accepted",
          preload: [:friend_user]
      )
      |> Enum.map(fn f -> %{user: f.friend_user, friendship: f, direction: :outgoing} end)

    # Friends who added me
    friends_of_me =
      Repo.all(
        from f in Friendship,
          where: f.friend_user_id == ^user_id and f.status == "accepted",
          preload: [:user]
      )
      |> Enum.map(fn f -> %{user: f.user, friendship: f, direction: :incoming} end)

    # Combine and dedupe by user id
    (my_friends ++ friends_of_me)
    |> Enum.uniq_by(fn %{user: u} -> u.id end)
  end

  def list_friend_requests(user_id) do
    Repo.all(
      from f in Friendship,
        where: f.friend_user_id == ^user_id and f.status == "pending",
        preload: [:user]
    )
  end

  def list_sent_friend_requests(user_id) do
    Repo.all(
      from f in Friendship,
        where: f.user_id == ^user_id and f.status == "pending",
        preload: [:friend_user]
    )
  end

  def count_friends(user_id) do
    my_count =
      Repo.one(
        from f in Friendship,
          where: f.user_id == ^user_id and f.status == "accepted",
          select: count(f.id)
      )

    their_count =
      Repo.one(
        from f in Friendship,
          where: f.friend_user_id == ^user_id and f.status == "accepted",
          select: count(f.id)
      )

    my_count + their_count
  end
  
  def get_friend_network_ids(user_id) do
    # Get friends I added (accepted)
    my_friends =
      Repo.all(
        from f in Friendship,
          where: f.user_id == ^user_id and f.status == "accepted",
          select: f.friend_user_id
      )

    # Get people who added me as friend (accepted)
    friends_of_me =
      Repo.all(
        from f in Friendship,
          where: f.friend_user_id == ^user_id and f.status == "accepted",
          select: f.user_id
      )

    # Combine (no self!), converting to string user_ids
    friend_ids =
      (my_friends ++ friends_of_me)
      |> Enum.uniq()
      |> Enum.map(&"user-#{&1}")

    friend_ids
  end

  # --- Invites ---

  def validate_invite(code) when is_binary(code) do
    admin_code = Application.get_env(:friends, :admin_invite_code)

    if admin_code && code == admin_code do
      {:ok, %Invite{code: admin_code, status: "active", created_by_id: nil, expires_at: nil}}
    else
      case Repo.get_by(Invite, code: code, status: "active") do
        nil ->
          {:error, :invalid_invite}

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

  def use_invite(invite, user) do
    invite
    |> Invite.changeset(%{
      status: "used",
      used_by_id: user.id,
      used_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  def list_user_invites(user_id) do
    Repo.all(
      from i in Invite,
        where: i.created_by_id == ^user_id,
        order_by: [desc: i.inserted_at],
        preload: [:used_by]
    )
  end

  def get_invite_by_code(code) do
    Repo.get_by(Invite, code: code)
  end

  def update_invite(%Invite{} = invite, attrs) do
    invite
    |> Invite.changeset(attrs)
    |> Repo.update()
  end
  
  # --- Recovery ---
  
  def request_recovery(_username) do
    # Requires User alias or Repo + Ecto query to find User
    # Assuming get_user_by_username logic is needed here too?
    # Or just query directly.
    
    # We will need Friends.Social.get_user_by_username
    # BUT Friends.Social will delegate to US.
    # So we need to query user here.
    # Where does User logic live?
    # User identity logic is still in Social or should be in Friends.Social.Identity (or Users).
    # The plan didn't specify an Identity module.
    # I'll put User/Identity functions in `Friends.Social` for now as they are core to "Social" context?
    # OR create Friends.Social.Identity?
    # List of new modules: Rooms, Photos, Notes, Chat, Relationships.
    # Identity is missing. 
    # I should probably leave User/Device/WebAuthn logic in `Friends.Social` or create `Friends.Social.Identity`.
    # Let's leave it in `Friends.Social` for now as the "Core" module, 
    # and just move the specific domain logic out.
    
    # Recovery involves Votes (Relationships/Trust).
    # So `cast_recovery_vote` belongs here.
    # `request_recovery` modifies User.
    
    # I'll implement `cast_recovery_vote` here.
    nil
  end
  
  # Wait, `request_recovery` modifies user status. It might fit better in Identity/User logic.
  # Let's keep `request_recovery` in `Friends.Social` (Identity).
  
  # `cast_recovery_vote` interacts with RecoveryVote and TrustedFriend. Fits well here.
  
  def cast_recovery_vote(recovering_user_id, voting_user_id, vote, new_public_key) do
    # Verify voter is a trusted friend first (outside transaction for fast fail)
    case get_trusted_friend_request(recovering_user_id, voting_user_id) do
      nil ->
        {:error, :not_trusted_friend}

      tf when tf.status != "confirmed" ->
        {:error, :not_confirmed_friend}

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

  defp check_recovery_threshold_internal(user_id, new_public_key) do
    confirm_count =
      Repo.one(
        from rv in RecoveryVote,
          where:
            rv.recovering_user_id == ^user_id and
              rv.vote == "confirm" and
              fragment("?::jsonb = ?::jsonb", rv.new_public_key, ^new_public_key),
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

  def check_recovery_threshold(user_id, new_public_key) do
    confirm_count =
      Repo.one(
        from rv in RecoveryVote,
          where:
            rv.recovering_user_id == ^user_id and
              rv.vote == "confirm" and
              fragment("?::jsonb = ?::jsonb", rv.new_public_key, ^new_public_key),
          select: count(rv.id)
      )

    if confirm_count >= 4 do
      {:ok, :threshold_met, confirm_count}
    else
      {:ok, :votes_recorded, confirm_count}
    end
  end

  def get_recovery_status(user_id) do
    votes =
      Repo.all(
        from rv in RecoveryVote,
          where: rv.recovering_user_id == ^user_id,
          preload: [:voting_user]
      )

    trusted_count = count_trusted_friends(user_id)
    confirm_votes = Enum.count(votes, &(&1.vote == "confirm"))

    %{
      votes: votes,
      trusted_friends: trusted_count,
      confirmations: confirm_votes,
      needed: 4,
      can_recover: confirm_votes >= 4
    }
  end

  def list_recovery_requests_for_voter(voter_user_id) do
    Repo.all(
      from u in User,
        join: tf in TrustedFriend,
        on:
          tf.user_id == u.id and tf.trusted_user_id == ^voter_user_id and tf.status == "confirmed",
        where: u.status == "recovering",
        select: u
    )
  end

  def has_voted_for_recovery?(recovering_user_id, voter_user_id) do
    Repo.exists?(
      from rv in RecoveryVote,
        where:
          rv.recovering_user_id == ^recovering_user_id and rv.voting_user_id == ^voter_user_id
    )
  end

  def get_recovery_public_key(recovering_user_id) do
    Repo.one(
      from rv in RecoveryVote,
        where: rv.recovering_user_id == ^recovering_user_id,
        order_by: [desc: rv.inserted_at],
        limit: 1,
        select: rv.new_public_key
    )
  end
  
  # --- Broadcast helper used by Photos ---
  
  def broadcast_to_contacts(user_id, event, payload) do
    # Get contact integer IDs
    my_friends =
      Repo.all(
        from f in Friendship,
          where: f.user_id == ^user_id and f.status == "accepted",
          select: f.friend_user_id
      )

    friends_of_me =
      Repo.all(
        from f in Friendship,
          where: f.friend_user_id == ^user_id and f.status == "accepted",
          select: f.user_id
      )

    contact_ids = (my_friends ++ friends_of_me) |> Enum.uniq()

    Enum.each(contact_ids, fn contact_id ->
      Phoenix.PubSub.broadcast(
        Friends.PubSub,
        "friends:public_feed:#{contact_id}",
        {event, payload}
      )
    end)

    # Also broadcast to self so own posts appear immediately
    Phoenix.PubSub.broadcast(
      Friends.PubSub,
      "friends:public_feed:#{user_id}",
      {event, payload}
    )
  end
  
  # --- Misc Helper ---
  
  def get_contact_user_ids(user_id) do
    get_friend_network_ids(user_id)
  end
  
  # Included for backwards compatibility or clarity
  def create_mutual_trust(user_a_id, user_b_id) do
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
end
