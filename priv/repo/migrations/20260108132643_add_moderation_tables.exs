defmodule Friends.Repo.Migrations.AddModerationTables do
  use Ecto.Migration

  def change do
    create table(:blocks) do
      add :blocker_id, references(:friends_users, on_delete: :delete_all)
      add :blocked_id, references(:friends_users, on_delete: :delete_all)
      timestamps()
    end

    create unique_index(:blocks, [:blocker_id, :blocked_id])

    create table(:reports) do
      add :reporter_id, references(:friends_users, on_delete: :delete_all)
      add :reported_id, references(:friends_users, on_delete: :delete_all)
      add :reason, :string
      add :status, :string, default: "pending"
      timestamps()
    end
  end
end
