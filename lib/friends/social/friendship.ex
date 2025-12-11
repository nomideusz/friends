defmodule Friends.Social.Friendship do
  @moduledoc """
  Friendship relationship for social connections.
  Unlike TrustedFriend (which is for account recovery), this represents
  a social connection where users can see each other's content.
  
  There is no limit on the number of friends a user can have.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "friends_friendships" do
    belongs_to :user, Friends.Social.User
    belongs_to :friend_user, Friends.Social.User
    
    # pending = request sent, accepted = mutual friends, blocked = blocked
    field :status, :string, default: "pending"
    field :accepted_at, :utc_datetime
    
    timestamps()
  end

  def changeset(friendship, attrs) do
    friendship
    |> cast(attrs, [:user_id, :friend_user_id, :status, :accepted_at])
    |> validate_required([:user_id, :friend_user_id])
    |> validate_inclusion(:status, ["pending", "accepted", "blocked"])
    |> unique_constraint([:user_id, :friend_user_id], name: :friends_friendships_user_friend_unique)
    |> check_constraint(:self_friend, name: :no_self_friend, message: "cannot befriend yourself")
  end
end
