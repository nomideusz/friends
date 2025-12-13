defmodule Friends.Social.RecoveryVote do
  @moduledoc """
  Votes from trusted friends during account recovery.
  Requires 4 out of 5 trusted friends to confirm identity.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "friends_recovery_votes" do
    belongs_to :recovering_user, Friends.Social.User
    belongs_to :voting_user, Friends.Social.User

    # confirm, deny
    field :vote, :string
    # The new public key being vouched for
    field :new_public_key, :map

    timestamps()
  end

  def changeset(vote, attrs) do
    vote
    |> cast(attrs, [:recovering_user_id, :voting_user_id, :vote, :new_public_key])
    |> validate_required([:recovering_user_id, :voting_user_id, :vote, :new_public_key])
    |> validate_inclusion(:vote, ["confirm", "deny"])
    |> unique_constraint([:recovering_user_id, :voting_user_id, :new_public_key],
      name: :friends_recovery_votes_unique
    )
  end
end
