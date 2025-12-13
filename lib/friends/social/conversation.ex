defmodule Friends.Social.Conversation do
  @moduledoc """
  Conversations for direct messages and group chats.
  Supports both 1:1 and multi-participant encrypted messaging.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Friends.Social.{User, ConversationParticipant, Message}

  schema "friends_conversations" do
    # "direct" or "group"
    field :type, :string, default: "direct"
    # For group chats
    field :name, :string

    belongs_to :created_by, User, foreign_key: :created_by_id
    has_many :participants, ConversationParticipant
    has_many :messages, Message

    timestamps()
  end

  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:type, :name, :created_by_id])
    |> validate_required([:type])
    |> validate_inclusion(:type, ["direct", "group", "room"])
    |> validate_group_name()
  end

  defp validate_group_name(changeset) do
    type = get_field(changeset, :type)

    if type == "group" do
      validate_required(changeset, [:name])
    else
      changeset
    end
  end
end
