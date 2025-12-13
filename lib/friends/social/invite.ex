defmodule Friends.Social.Invite do
  @moduledoc """
  Invite codes for joining the network.
  Each user can generate invites for friends.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "friends_invites" do
    belongs_to :created_by, Friends.Social.User
    belongs_to :used_by, Friends.Social.User

    field :code, :string
    # active, used, revoked
    field :status, :string, default: "active"
    field :used_at, :utc_datetime
    field :expires_at, :utc_datetime

    timestamps()
  end

  def changeset(invite, attrs) do
    invite
    |> cast(attrs, [:created_by_id, :used_by_id, :code, :status, :used_at, :expires_at])
    |> validate_required([:code])
    |> validate_inclusion(:status, ["active", "used", "revoked"])
    |> unique_constraint(:code)
  end

  @doc """
  Generate a human-friendly invite code
  """
  def generate_code do
    # Format: word-word-number (easy to share verbally)
    adjectives = ~w(swift calm warm cool soft deep wild free bold pure brave kind wise fair)
    nouns = ~w(wave tide peak vale cove glen bay dune reef isle moon star sun rain)

    adj = Enum.random(adjectives)
    noun = Enum.random(nouns)
    num = :rand.uniform(999)

    "#{adj}-#{noun}-#{num}"
  end
end
