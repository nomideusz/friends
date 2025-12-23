defmodule Friends.Social.Message do
  @moduledoc """
  Encrypted messages in conversations.
  Content is E2E encrypted - server only stores encrypted blobs.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Friends.Social.{User, Conversation}

  # 60 seconds
  @max_voice_duration_ms 60_000

  schema "friends_messages" do
    belongs_to :conversation, Conversation
    belongs_to :room, Friends.Social.Room
    belongs_to :sender, User, foreign_key: :sender_id
    belongs_to :reply_to, __MODULE__, foreign_key: :reply_to_id

    # E2E encrypted
    field :encrypted_content, :binary
    # "text", "voice", "image"
    field :content_type, :string, default: "text"
    # duration_ms for voice, dimensions for image
    field :metadata, :map, default: %{}
    # Encryption nonce/IV
    field :nonce, :binary

    timestamps()
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [
      :conversation_id,
      :room_id,
      :sender_id,
      :encrypted_content,
      :content_type,
      :metadata,
      :nonce,
      :reply_to_id
    ])
    |> validate_required([:sender_id, :encrypted_content, :content_type])
    |> validate_inclusion(:content_type, ["text", "voice", "image"])
    |> validate_voice_duration()
    |> validate_conversation_or_room()
  end

  defp validate_conversation_or_room(changeset) do
    conversation_id = get_field(changeset, :conversation_id)
    room_id = get_field(changeset, :room_id)

    if is_nil(conversation_id) and is_nil(room_id) do
      add_error(changeset, :base, "message must belong to either a conversation or a room")
    else
      changeset
    end
  end

  defp validate_voice_duration(changeset) do
    content_type = get_field(changeset, :content_type)
    metadata = get_field(changeset, :metadata) || %{}

    if content_type == "voice" do
      duration = metadata["duration_ms"] || metadata[:duration_ms] || 0

      if duration > @max_voice_duration_ms do
        add_error(changeset, :metadata, "voice note exceeds maximum duration of 60 seconds")
      else
        changeset
      end
    else
      changeset
    end
  end

  def max_voice_duration_ms, do: @max_voice_duration_ms
end
