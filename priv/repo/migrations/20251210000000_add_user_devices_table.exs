defmodule Friends.Repo.Migrations.AddUserDevicesTable do
  use Ecto.Migration

  def change do
    # User devices - track all devices that have accessed a user account
    create table(:friends_user_devices) do
      add :user_id, references(:friends_users, on_delete: :delete_all), null: false
      add :device_fingerprint, :string, null: false
      add :device_name, :string
      add :public_key_fingerprint, :string
      add :last_seen_at, :utc_datetime
      add :first_seen_at, :utc_datetime
      add :trusted, :boolean, default: true
      add :revoked, :boolean, default: false

      timestamps()
    end

    create index(:friends_user_devices, [:user_id])
    create index(:friends_user_devices, [:device_fingerprint])
    create index(:friends_user_devices, [:user_id, :trusted])
  end
end
