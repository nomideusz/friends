defmodule Friends.Repo.Migrations.MakePublicKeyNullable do
  use Ecto.Migration

  def change do
    alter table(:friends_users) do
      modify :public_key, :map, null: true
    end
  end
end
