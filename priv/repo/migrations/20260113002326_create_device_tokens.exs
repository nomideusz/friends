defmodule Friends.Repo.Migrations.CreateDeviceTokens do
  use Ecto.Migration

  def change do
    create table(:device_tokens) do
      add :token, :string, null: false
      add :platform, :string, null: false
      add :user_id, references(:friends_users, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:device_tokens, [:token, :user_id])
    create index(:device_tokens, [:user_id])
  end
end
