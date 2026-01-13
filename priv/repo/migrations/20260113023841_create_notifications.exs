defmodule Friends.Repo.Migrations.CreateNotifications do
  use Ecto.Migration

  def change do
    create table(:friends_notifications) do
      add :user_id, references(:friends_users, on_delete: :delete_all), null: false
      add :type, :string, null: false  # message, friend_request, trust_request, group_invite, connection_accepted, trust_confirmed
      add :read, :boolean, default: false, null: false

      # Actor info (who triggered the notification)
      add :actor_id, references(:friends_users, on_delete: :nilify_all)
      add :actor_username, :string
      add :actor_color, :string
      add :actor_avatar_url, :string

      # Context info (varies by type)
      add :room_id, references(:friends_rooms, on_delete: :delete_all)
      add :room_code, :string
      add :room_name, :string
      add :conversation_id, references(:friends_conversations, on_delete: :delete_all)

      # Display content
      add :text, :string
      add :preview, :text

      # Grouping support
      add :group_key, :string
      add :count, :integer, default: 1

      timestamps()
    end

    create index(:friends_notifications, [:user_id])
    create index(:friends_notifications, [:user_id, :read])
    create index(:friends_notifications, [:user_id, :inserted_at])
    create index(:friends_notifications, [:group_key])
  end
end
