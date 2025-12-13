defmodule Friends.Social.RoomMember do
  @moduledoc """
  Room membership for private rooms.
  Tracks who has access to a private room.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "friends_room_members" do
    belongs_to :room, Friends.Social.Room
    belongs_to :user, Friends.Social.User
    belongs_to :invited_by, Friends.Social.User

    # owner, admin, member
    field :role, :string, default: "member"

    timestamps()
  end

  def changeset(member, attrs) do
    member
    |> cast(attrs, [:room_id, :user_id, :role, :invited_by_id])
    |> validate_required([:room_id, :user_id])
    |> validate_inclusion(:role, ["owner", "admin", "member"])
    |> unique_constraint([:room_id, :user_id])
  end
end
