defmodule Friends.Repo.Migrations.AddBatchIdToPhotos do
  use Ecto.Migration

  def change do
    alter table(:friends_photos) do
      add :batch_id, :string
    end

    create index(:friends_photos, [:batch_id])
  end
end
