defmodule Friends.Social.Photo do
  use Ecto.Schema
  import Ecto.Changeset

  # Use existing friends_photos table from rzeczywiscie
  schema "friends_photos" do
    field :user_id, :string
    field :user_color, :string
    field :user_name, :string
    field :image_data, :string  # Original URL (backwards compatible)
    field :thumbnail_data, :string  # Legacy field, kept for compatibility
    field :image_url_thumb, :string  # 400px thumbnail
    field :image_url_medium, :string  # 800px for feed
    field :image_url_large, :string  # 1600px for lightbox
    field :content_type, :string
    field :file_size, :integer
    field :description, :string
    field :uploaded_at, :utc_datetime
    field :batch_id, :string  # Groups photos uploaded together

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
      :image_url_thumb,
      :image_url_medium,
      :image_url_large,
      :content_type,
      :file_size,
      :description,
      :room_id,
      :batch_id
    ])
    |> validate_required([:user_id, :image_data])
    |> validate_length(:description, max: 200)
    |> put_change(:uploaded_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end

  @doc """
  Returns the best available thumbnail URL, falling back through sizes.
  """
  def thumbnail_url(photo) do
    photo.image_url_thumb || photo.thumbnail_data || photo.image_data
  end

  @doc """
  Returns the best available medium URL for feed display.
  """
  def medium_url(photo) do
    photo.image_url_medium || photo.image_data
  end

  @doc """
  Returns the best available large URL for lightbox.
  """
  def large_url(photo) do
    photo.image_url_large || photo.image_data
  end

  @doc """
  Returns the original URL for download.
  """
  def original_url(photo) do
    photo.image_data
  end
end

