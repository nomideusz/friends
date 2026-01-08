defmodule Friends.Social.Block do
  use Ecto.Schema
  import Ecto.Changeset

  schema "blocks" do
    belongs_to :blocker, Friends.Social.User
    belongs_to :blocked, Friends.Social.User

    timestamps()
  end

  def changeset(block, attrs) do
    block
    |> cast(attrs, [:blocker_id, :blocked_id])
    |> validate_required([:blocker_id, :blocked_id])
    |> unique_constraint([:blocker_id, :blocked_id])
  end
end
