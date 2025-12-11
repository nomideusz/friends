defmodule Friends.Social.ConversationParticipant do
  @moduledoc """
  Participants in a conversation with their encrypted conversation keys.
  Each participant has the conversation's symmetric key encrypted with their public key.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Friends.Social.{User, Conversation}

  schema "friends_conversation_participants" do
    belongs_to :conversation, Conversation
    belongs_to :user, User

    field :encrypted_key, :binary  # Conversation key encrypted with user's public key
    field :role, :string, default: "member"  # "owner", "admin", "member"
    field :last_read_at, :utc_datetime
    field :muted, :boolean, default: false

    timestamps()
  end

  def changeset(participant, attrs) do
    participant
    |> cast(attrs, [:conversation_id, :user_id, :encrypted_key, :role, :last_read_at, :muted])
    |> validate_required([:conversation_id, :user_id])
    |> validate_inclusion(:role, ["owner", "admin", "member"])
    |> unique_constraint([:conversation_id, :user_id])
  end
end
