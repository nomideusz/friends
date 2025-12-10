defmodule Friends.Repo.Migrations.AddWebauthnCredentialsTable do
  use Ecto.Migration

  def change do
    # WebAuthn credentials - hardware keys, biometrics, etc.
    create table(:friends_webauthn_credentials) do
      add :user_id, references(:friends_users, on_delete: :delete_all), null: false
      add :credential_id, :binary, null: false
      add :public_key, :binary, null: false
      add :sign_count, :bigint, default: 0
      add :transports, {:array, :string}, default: []
      add :aaguid, :binary
      add :credential_type, :string, default: "public-key"
      add :name, :string
      add :last_used_at, :utc_datetime

      timestamps()
    end

    create index(:friends_webauthn_credentials, [:user_id])
    create unique_index(:friends_webauthn_credentials, [:credential_id])
  end
end
