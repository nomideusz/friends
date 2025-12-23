defmodule Friends.Repo.Migrations.CreateDevicePairings do
  use Ecto.Migration

  def change do
    create table(:friends_device_pairings) do
      add :user_id, references(:friends_users, on_delete: :delete_all), null: false
      add :token, :string, null: false
      add :expires_at, :utc_datetime, null: false
      add :claimed, :boolean, default: false, null: false
      add :device_name, :string

      timestamps()
    end

    create unique_index(:friends_device_pairings, [:token])
    create index(:friends_device_pairings, [:user_id])
    create index(:friends_device_pairings, [:expires_at])
  end
end
