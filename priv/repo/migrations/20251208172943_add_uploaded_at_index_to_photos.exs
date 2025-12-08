defmodule Friends.Repo.Migrations.AddUploadedAtIndexToPhotos do
  use Ecto.Migration

  def change do
    create_if_not_exists index(:friends_photos, [:uploaded_at])
  end
end
