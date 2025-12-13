defmodule Friends.Repo.Migrations.AddImageUrlVariantsToPhotos do
  use Ecto.Migration

  def change do
    alter table(:friends_photos) do
      add :image_url_thumb, :text
      add :image_url_medium, :text
      add :image_url_large, :text
      # image_data will continue to hold the original URL for backwards compatibility
    end
  end
end
