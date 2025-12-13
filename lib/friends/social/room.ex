defmodule Friends.Social.Room do
  use Ecto.Schema
  import Ecto.Changeset

  schema "friends_rooms" do
    field :code, :string
    field :name, :string
    field :emoji, :string, default: ""
    field :created_by, :string
    field :is_private, :boolean, default: false
    # "public", "private", "dm"
    field :room_type, :string, default: "public"

    belongs_to :owner, Friends.Social.User
    has_many :photos, Friends.Social.Photo
    has_many :notes, Friends.Social.Note
    has_many :messages, Friends.Social.Message
    has_many :members, Friends.Social.RoomMember

    timestamps()
  end

  def changeset(room, attrs) do
    room
    |> cast(attrs, [:code, :name, :emoji, :created_by, :is_private, :owner_id, :room_type])
    |> validate_required([:code])
    |> validate_length(:code, min: 2, max: 32)
    |> validate_format(:code, ~r/^[a-z0-9-]+$/,
      message: "lowercase letters, numbers, dashes only"
    )
    |> validate_inclusion(:room_type, ["public", "private", "dm"])
    |> unique_constraint(:code)
  end

  # Helper functions
  def dm?(%__MODULE__{room_type: "dm"}), do: true
  def dm?(_), do: false

  def private?(%__MODULE__{is_private: true}), do: true
  def private?(%__MODULE__{room_type: type}) when type in ["private", "dm"], do: true
  def private?(_), do: false

  def public?(%__MODULE__{is_private: false, room_type: "public"}), do: true
  def public?(_), do: false
end
