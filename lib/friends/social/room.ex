defmodule Friends.Social.Room do
  use Ecto.Schema
  import Ecto.Changeset

  schema "friends_rooms" do
    field :code, :string
    field :name, :string
    field :emoji, :string, default: ""
    field :created_by, :string
    field :is_private, :boolean, default: false
    
    belongs_to :owner, Friends.Social.User
    has_many :photos, Friends.Social.Photo
    has_many :notes, Friends.Social.Note
    has_many :members, Friends.Social.RoomMember

    timestamps()
  end

  def changeset(room, attrs) do
    room
    |> cast(attrs, [:code, :name, :emoji, :created_by, :is_private, :owner_id])
    |> validate_required([:code])
    |> validate_length(:code, min: 2, max: 32)
    |> validate_format(:code, ~r/^[a-z0-9-]+$/, message: "lowercase letters, numbers, dashes only")
    |> unique_constraint(:code)
  end
end

