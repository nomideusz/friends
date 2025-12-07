defmodule Friends.Repo.Migrations.CreateIdentityTables do
  use Ecto.Migration

  def change do
    # Users - the core identity
    create table(:friends_users) do
      add :username, :string, size: 20, null: false
      add :public_key, :map, null: false
      add :display_name, :string, size: 50
      add :status, :string, size: 20, default: "active"
      add :invited_by_id, :bigint
      add :invite_code, :string
      add :recovery_requested_at, :utc_datetime

      timestamps()
    end

    create unique_index(:friends_users, [:username])
    create unique_index(:friends_users, [:public_key])

    # Invites - how new users join
    create table(:friends_invites) do
      add :created_by_id, references(:friends_users, on_delete: :nilify_all)
      add :used_by_id, references(:friends_users, on_delete: :nilify_all)
      add :code, :string, size: 50, null: false
      add :status, :string, size: 20, default: "active"
      add :used_at, :utc_datetime
      add :expires_at, :utc_datetime

      timestamps()
    end

    create unique_index(:friends_invites, [:code])
    create index(:friends_invites, [:created_by_id])
    create index(:friends_invites, [:status])

    # Trusted friends - for social recovery
    create table(:friends_trusted_friends) do
      add :user_id, references(:friends_users, on_delete: :delete_all), null: false
      add :trusted_user_id, references(:friends_users, on_delete: :delete_all), null: false
      add :status, :string, size: 20, default: "pending"
      add :confirmed_at, :utc_datetime

      timestamps()
    end

    create unique_index(:friends_trusted_friends, [:user_id, :trusted_user_id], 
                        name: :friends_trusted_friends_user_trusted_unique)
    create index(:friends_trusted_friends, [:trusted_user_id])
    
    # Constraint: can't trust yourself
    create constraint(:friends_trusted_friends, :no_self_trust, 
                      check: "user_id != trusted_user_id")

    # Recovery votes - friends vouching for identity
    create table(:friends_recovery_votes) do
      add :recovering_user_id, references(:friends_users, on_delete: :delete_all), null: false
      add :voting_user_id, references(:friends_users, on_delete: :delete_all), null: false
      add :vote, :string, size: 20, null: false
      add :new_public_key, :map, null: false

      timestamps()
    end

    create unique_index(:friends_recovery_votes, 
                        [:recovering_user_id, :voting_user_id], 
                        name: :friends_recovery_votes_unique)
    create index(:friends_recovery_votes, [:recovering_user_id])

    # Link existing device_links to users
    alter table(:friends_device_links) do
      add :user_id, references(:friends_users, on_delete: :nilify_all)
    end
    
    create index(:friends_device_links, [:user_id])

    # Create initial "founder" invite (bootstrapping)
    execute """
    INSERT INTO friends_invites (code, status, inserted_at, updated_at) 
    VALUES ('founder-alpha-001', 'active', NOW(), NOW())
    """, ""
  end
end


