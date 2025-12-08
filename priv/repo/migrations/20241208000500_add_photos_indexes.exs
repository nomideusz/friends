defmodule Friends.Repo.Migrations.AddPhotosIndexes do
  use Ecto.Migration

  def change do
    create_if_not_exists index(:friends_photos, [:room_id, :uploaded_at, :inserted_at])
    create_if_not_exists index(:friends_photos, [:uploaded_at, :inserted_at])
  end
end

