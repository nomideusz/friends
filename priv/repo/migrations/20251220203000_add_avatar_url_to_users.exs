defmodule Friends.Repo.Migrations.AddAvatarUrlToUsers do
  use Ecto.Migration

  def change do
    alter table(:friends_users) do
      add :avatar_url, :string
      add :user_color, :string
    end
  end
end
