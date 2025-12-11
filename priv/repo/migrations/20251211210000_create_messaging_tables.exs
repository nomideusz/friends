defmodule Friends.Repo.Migrations.CreateMessagingTables do
  use Ecto.Migration

  def change do
    # Conversations table (1:1 or group chats)
    create table(:friends_conversations) do
      add :type, :string, null: false, default: "direct"  # "direct" or "group"
      add :name, :string  # For group chats
      add :created_by_id, references(:friends_users, on_delete: :nilify_all)

      timestamps()
    end

    create index(:friends_conversations, [:created_by_id])
    create index(:friends_conversations, [:type])

    # Conversation participants
    create table(:friends_conversation_participants) do
      add :conversation_id, references(:friends_conversations, on_delete: :delete_all), null: false
      add :user_id, references(:friends_users, on_delete: :delete_all), null: false
      add :encrypted_key, :binary  # Conversation symmetric key encrypted with user's public key
      add :role, :string, default: "member"  # "owner", "admin", "member"
      add :last_read_at, :utc_datetime
      add :muted, :boolean, default: false

      timestamps()
    end

    create index(:friends_conversation_participants, [:conversation_id])
    create index(:friends_conversation_participants, [:user_id])
    create unique_index(:friends_conversation_participants, [:conversation_id, :user_id])

    # Messages table (encrypted content)
    create table(:friends_messages) do
      add :conversation_id, references(:friends_conversations, on_delete: :delete_all), null: false
      add :sender_id, references(:friends_users, on_delete: :nilify_all)
      add :encrypted_content, :binary, null: false  # E2E encrypted message content
      add :content_type, :string, null: false, default: "text"  # "text", "voice", "image"
      add :metadata, :map, default: %{}  # duration_ms for voice, dimensions for image
      add :nonce, :binary  # Encryption nonce/IV
      add :reply_to_id, references(:friends_messages, on_delete: :nilify_all)

      timestamps()
    end

    create index(:friends_messages, [:conversation_id])
    create index(:friends_messages, [:sender_id])
    create index(:friends_messages, [:inserted_at])
  end
end
