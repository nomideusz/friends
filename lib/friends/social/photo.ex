defmodule Friends.Social.Photo do
  use Ecto.Schema
  import Ecto.Changeset

  # Use existing friends_photos table from rzeczywiscie
  schema "friends_photos" do
    field :user_id, :string
    field :user_color, :string
    field :user_name, :string
    field :image_data, :string
    field :thumbnail_data, :string
    field :content_type, :string
    field :file_size, :integer
    field :description, :string
    field :uploaded_at, :utc_datetime

    belongs_to :room, Friends.Social.Room

    timestamps()
  end

  def changeset(photo, attrs) do
    photo
    |> cast(attrs, [
      :user_id,
      :user_color,
      :user_name,
      :image_data,
      :thumbnail_data,
      :content_type,
      :file_size,
      :description,
      :room_id
    ])
    |> validate_required([:user_id, :image_data])
    |> validate_length(:description, max: 200)
    |> put_change(:uploaded_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end
end
