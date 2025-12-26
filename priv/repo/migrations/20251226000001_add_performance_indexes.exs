defmodule Friends.Repo.Migrations.AddPerformanceIndexes do
  use Ecto.Migration

  def change do
    # Photos table - heavily queried by user_id and batch_id
    create_if_not_exists index(:friends_photos, [:user_id])
    create_if_not_exists index(:friends_photos, [:batch_id])
    create_if_not_exists index(:friends_photos, [:room_id, :inserted_at])

    # Text cards - queried by user_id
    create_if_not_exists index(:friends_text_cards, [:user_id])

    # Messages - queried by sender
    create_if_not_exists index(:friends_messages, [:sender_id])

    # Friendships - compound indexes for status filtering
    create_if_not_exists index(:friends_friendships, [:user_id, :status])
    create_if_not_exists index(:friends_friendships, [:friend_user_id, :status])

    # Room members - for quick membership lookups
    create_if_not_exists index(:friends_room_members, [:user_id, :room_id])
  end
end
