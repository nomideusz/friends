defmodule Friends.Social.Chat do
  @moduledoc """
  Manages Chat (Messages, Conversations).
  """
  import Ecto.Query, warn: false
  alias Friends.Repo
  alias Friends.Social.{Message, Conversation, ConversationParticipant}
  # alias Friends.Social.Rooms

  defp conversation_topic(conversation_id), do: "friends:conversation:#{conversation_id}"

  def subscribe_to_conversation(conversation_id) do
    Phoenix.PubSub.subscribe(Friends.PubSub, conversation_topic(conversation_id))
  end

  def subscribe_to_user_conversations(user_id) do
    Phoenix.PubSub.subscribe(Friends.PubSub, "friends:user_messages:#{user_id}")
  end

  def get_or_create_direct_conversation(user_a_id, user_b_id) do
    # Ensure consistent ordering for lookup
    [first_id, second_id] = Enum.sort([user_a_id, user_b_id])

    # Look for existing direct conversation with exactly these two participants
    existing =
      Repo.one(
        from c in Conversation,
          join: p1 in ConversationParticipant,
          on: p1.conversation_id == c.id,
          join: p2 in ConversationParticipant,
          on: p2.conversation_id == c.id,
          where:
            c.type == "direct" and
              p1.user_id == ^first_id and
              p2.user_id == ^second_id,
          group_by: c.id,
          having:
            count(fragment("DISTINCT ?", p1.id)) + count(fragment("DISTINCT ?", p2.id)) == 2,
          limit: 1
      )

    case existing do
      nil -> create_conversation(user_a_id, [user_b_id], "direct", nil)
      conversation -> {:ok, Repo.preload(conversation, [:participants])}
    end
  end

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

  def list_user_conversations(user_id) do
    Repo.all(
      from c in Conversation,
        join: p in ConversationParticipant,
        on: p.conversation_id == c.id,
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

  def get_latest_message(conversation_id) do
    Repo.one(
      from m in Message,
        where: m.conversation_id == ^conversation_id,
        order_by: [desc: m.inserted_at],
        limit: 1,
        preload: [:sender]
    )
  end

  def get_unread_count(conversation_id, user_id) do
    participant =
      Repo.one(
        from p in ConversationParticipant,
          where: p.conversation_id == ^conversation_id and p.user_id == ^user_id
      )

    case participant do
      nil ->
        0

      %{last_read_at: nil} ->
        Repo.aggregate(
          from(m in Message,
            where: m.conversation_id == ^conversation_id and m.sender_id != ^user_id
          ),
          :count
        )

      %{last_read_at: last_read} ->
        Repo.aggregate(
          from(m in Message,
            where:
              m.conversation_id == ^conversation_id and
                m.sender_id != ^user_id and
                m.inserted_at > ^last_read
          ),
          :count
        )
    end
  end

  def get_latest_unread_message(user_id) do
    Repo.one(
      from m in Message,
        join: p in ConversationParticipant,
        on: m.conversation_id == p.conversation_id,
        where: p.user_id == ^user_id,
        where: m.sender_id != ^user_id,
        where: is_nil(p.last_read_at) or m.inserted_at > p.last_read_at,
        order_by: [desc: m.inserted_at],
        limit: 1,
        preload: [:sender, :conversation]
    )
  end
  
  def get_total_unread_count(user_id) do
    # Efficiently sum unread counts across all conversations
    # This might be expensive if loop based.
    # We can use a query or existing logic.
    # The original social.ex logic:
    conversations =
      Repo.all(
        from p in ConversationParticipant,
          where: p.user_id == ^user_id,
          select: {p.conversation_id, p.last_read_at}
      )

    Enum.reduce(conversations, 0, fn {conv_id, last_read}, acc ->
      count =
        case last_read do
          nil ->
            Repo.aggregate(
              from(m in Message,
                where: m.conversation_id == ^conv_id and m.sender_id != ^user_id
              ),
              :count
            )

          dt ->
            Repo.aggregate(
              from(m in Message,
                where: m.conversation_id == ^conv_id and m.sender_id != ^user_id and m.inserted_at > ^dt
              ),
              :count
            )
        end

      acc + (count || 0)
    end)
  end

  def send_message(
        conversation_id,
        sender_id,
        encrypted_content,
        content_type,
        metadata \\ %{},
        nonce,
        reply_to_id \\ nil
      ) do
    # Verify sender is a participant
    participant =
      Repo.one(
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
          participants =
            Repo.all(
              from p in ConversationParticipant,
                where: p.conversation_id == ^conversation_id and p.user_id != ^sender_id,
                select: p.user_id
            )

          Enum.each(participants, fn user_id ->
            Phoenix.PubSub.broadcast(
              Friends.PubSub,
              "friends:user:#{user_id}",
              {:new_message_notification, %{conversation_id: conversation_id, message: message}}
            )
          end)

          {:ok, message}

        error ->
          error
      end
    end
  end

  def list_messages(conversation_id, limit \\ 50, offset \\ 0) do
    Repo.all(
      from m in Message,
        where: m.conversation_id == ^conversation_id,
        order_by: [desc: m.inserted_at],
        limit: ^limit,
        offset: ^offset,
        preload: [:sender, :reply_to]
    )
    # Return in chronological order
    |> Enum.reverse()
  end

  def mark_conversation_read(conversation_id, user_id) do
    Repo.update_all(
      from(p in ConversationParticipant,
        where: p.conversation_id == ^conversation_id and p.user_id == ^user_id
      ),
      set: [last_read_at: DateTime.utc_now()]
    )
  end

  def get_conversation(conversation_id) do
    Repo.get(Conversation, conversation_id)
    |> Repo.preload(participants: :user)
  end

  def is_participant?(conversation_id, user_id) do
    Repo.exists?(
      from p in ConversationParticipant,
        where: p.conversation_id == ^conversation_id and p.user_id == ^user_id
    )
  end

  def add_participant(conversation_id, user_id, added_by_id) do
    conversation = Repo.get(Conversation, conversation_id)

    cond do
      is_nil(conversation) ->
        {:error, :conversation_not_found}

      conversation.type != "group" ->
        {:error, :direct_messages_are_exclusive}

      not is_participant?(conversation_id, added_by_id) ->
        {:error, :not_authorized}

      is_participant?(conversation_id, user_id) ->
        {:error, :already_participant}

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
  
  # --- Room Chat (Legacy/Simple Chat) ---
  
  def list_room_messages(room_id, limit \\ 50) do
    Repo.all(
      from m in Message,
        where: m.room_id == ^room_id,
        order_by: [asc: m.inserted_at],
        limit: ^limit,
        preload: [:sender]
    )
  end

  def send_room_message(
        room_id,
        sender_id,
        content,
        type \\ "text",
        metadata \\ %{},
        nonce \\ nil
      ) do
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

        # Notify room members who are NOT the sender
        # Note: In a large system we'd check presence or use a different strategy,
        # but for this "New Internet" experience, global notifications are key.
        room = Repo.get(Friends.Social.Room, room_id)
        if room && room.is_private do
          # Get all members
          members = Friends.Social.Rooms.list_room_members(room_id)
          Enum.each(members, fn member ->
            if member.user_id != sender_id do
              Phoenix.PubSub.broadcast(
                Friends.PubSub,
                "friends:user:#{member.user_id}",
                {:new_message_notification, %{room_id: room_id, room_name: room.name, message: message}}
              )
            end
          end)
        end

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
end
