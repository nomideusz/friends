defmodule Friends.Repo.Migrations.AddPinnedAtToPhotosAndNotes do
  use Ecto.Migration

  def change do
    # Photos table is actually friends_photos
    alter table(:friends_photos) do
      add :pinned_at, :utc_datetime, null: true
    end

    # Notes table is actually friends_text_cards
    alter table(:friends_text_cards) do
      add :pinned_at, :utc_datetime, null: true
    end

    # Index for efficient pinned-first queries
    create index(:friends_photos, [:room_id, :pinned_at])
    create index(:friends_text_cards, [:room_id, :pinned_at])
  end
end
