defmodule Friends.Social.User do
  @moduledoc """
  User identity - username + WebAuthn passkeys.
  No passwords, no emails. Identity is verified via:
  1. WebAuthn passkeys (hardware keys, biometrics)
  2. Trusted friends (account recovery)
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "friends_users" do
    field :username, :string
    # Legacy - kept for backward compatibility, nil for WebAuthn-only users
    field :public_key, :map
    field :display_name, :string
    # active, suspended, recovering
    field :status, :string, default: "active"

    # Invite system
    field :invited_by_id, :integer
    field :invite_code, :string

    # Recovery
    field :recovery_requested_at, :utc_datetime

    timestamps()
  end

  @username_regex ~r/^[a-z0-9_]{3,20}$/

  def changeset(user, attrs) do
    user
    |> cast(attrs, [
      :username,
      :public_key,
      :display_name,
      :status,
      :invited_by_id,
      :invite_code,
      :recovery_requested_at
    ])
    |> validate_required([:username])
    |> validate_format(:username, @username_regex,
      message: "must be 3-20 lowercase letters, numbers, or underscores"
    )
    |> validate_length(:display_name, max: 50)
    |> unique_constraint(:username)
  end

  def registration_changeset(user, attrs) do
    user
    |> changeset(attrs)
  end
end
