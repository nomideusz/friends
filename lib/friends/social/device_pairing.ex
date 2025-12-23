defmodule Friends.Social.DevicePairing do
  @moduledoc """
  Schema for device pairing tokens.
  Enables users to add new devices by generating a temporary token
  that can be used to register a new WebAuthn credential.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @token_length 8
  @token_chars ~c"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

  schema "friends_device_pairings" do
    field :token, :string
    field :expires_at, :utc_datetime
    field :claimed, :boolean, default: false
    field :device_name, :string

    belongs_to :user, Friends.Social.User

    timestamps()
  end

  def changeset(pairing, attrs) do
    pairing
    |> cast(attrs, [:user_id, :token, :expires_at, :claimed, :device_name])
    |> validate_required([:user_id, :token, :expires_at])
    |> unique_constraint(:token)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Generate a random, human-friendly pairing token.
  Uses uppercase letters and digits, excluding confusing characters (0, O, 1, I, L).
  """
  def generate_token do
    for _ <- 1..@token_length, into: "" do
      <<Enum.random(@token_chars)>>
    end
  end

  @doc """
  Get expiry time (5 minutes from now).
  """
  def default_expiry do
    DateTime.utc_now()
    |> DateTime.add(5, :minute)
    |> DateTime.truncate(:second)
  end
end
