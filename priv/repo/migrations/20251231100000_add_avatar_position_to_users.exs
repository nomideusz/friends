defmodule Friends.Repo.Migrations.AddAvatarPositionToUsers do
  use Ecto.Migration

  def change do
    alter table(:friends_users) do
      add :avatar_position, :string, default: "top-right"
    end
  end
end
