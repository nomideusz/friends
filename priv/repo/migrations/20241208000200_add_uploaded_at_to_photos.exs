defmodule Friends.Repo.Migrations.AddUploadedAtToPhotos do
  use Ecto.Migration

  def change do
    alter table(:friends_photos) do
      add_if_not_exists :uploaded_at, :utc_datetime
    end
  end
end

