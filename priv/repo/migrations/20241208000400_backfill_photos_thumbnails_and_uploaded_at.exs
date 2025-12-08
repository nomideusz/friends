defmodule Friends.Repo.Migrations.BackfillPhotosThumbnailsAndUploadedAt do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE friends_photos
    SET thumbnail_data = image_data
    WHERE thumbnail_data IS NULL
    """)

    execute("""
    UPDATE friends_photos
    SET uploaded_at = inserted_at
    WHERE uploaded_at IS NULL
    """)
  end

  def down do
    :ok
  end
end

