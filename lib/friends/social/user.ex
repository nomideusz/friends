defmodule Friends.Social.User do
  @moduledoc """
  User identity - username + cryptographic public key.
  No passwords, no emails. Identity is verified via:
  1. Browser crypto key (primary)
  2. Trusted friends (recovery)
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "friends_users" do
    field :username, :string
    field :public_key, :map  # JWK format
    field :display_name, :string
    field :status, :string, default: "active"  # active, suspended, recovering
    
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
    |> cast(attrs, [:username, :public_key, :display_name, :status, :invited_by_id, :invite_code, :recovery_requested_at])
    |> validate_required([:username, :public_key])
    |> validate_format(:username, @username_regex, message: "must be 3-20 lowercase letters, numbers, or underscores")
    |> validate_length(:display_name, max: 50)
    |> unique_constraint(:username)
    |> unique_constraint(:public_key)
  end

  def registration_changeset(user, attrs) do
    user
    |> changeset(attrs)
    |> validate_required([:invite_code])
  end
end


