defmodule Friends.Social.TrustedFriend do
  @moduledoc """
  Trusted friend relationship for social recovery.
  A user can designate up to 5 trusted friends who can vouch for their identity.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "friends_trusted_friends" do
    belongs_to :user, Friends.Social.User
    belongs_to :trusted_user, Friends.Social.User
    
    field :status, :string, default: "pending"  # pending, confirmed, removed
    field :confirmed_at, :utc_datetime
    
    timestamps()
  end

  def changeset(trusted_friend, attrs) do
    trusted_friend
    |> cast(attrs, [:user_id, :trusted_user_id, :status, :confirmed_at])
    |> validate_required([:user_id, :trusted_user_id])
    |> validate_inclusion(:status, ["pending", "confirmed", "removed"])
    |> unique_constraint([:user_id, :trusted_user_id], name: :friends_trusted_friends_user_trusted_unique)
    |> check_constraint(:self_trust, name: :no_self_trust, message: "cannot trust yourself")
  end
end


