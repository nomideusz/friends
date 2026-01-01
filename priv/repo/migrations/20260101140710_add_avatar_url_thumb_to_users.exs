defmodule Friends.Repo.Migrations.AddAvatarUrlThumbToUsers do
  use Ecto.Migration

  def change do
    alter table(:friends_users) do
      add :avatar_url_thumb, :string
    end
  end
end
