defmodule Friends.Social.WebAuthnCredential do
  use Ecto.Schema
  import Ecto.Changeset

  schema "friends_webauthn_credentials" do
    field :credential_id, :binary
    field :public_key, :binary
    field :sign_count, :integer, default: 0
    field :transports, {:array, :string}, default: []
    field :aaguid, :binary
    field :credential_type, :string, default: "public-key"
    field :name, :string
    field :last_used_at, :utc_datetime

    belongs_to :user, Friends.Social.User

    timestamps()
  end

  def changeset(credential, attrs) do
    credential
    |> cast(attrs, [
      :user_id,
      :credential_id,
      :public_key,
      :sign_count,
      :transports,
      :aaguid,
      :credential_type,
      :name,
      :last_used_at
    ])
    |> validate_required([:user_id, :credential_id, :public_key])
    |> unique_constraint(:credential_id)
  end
end
