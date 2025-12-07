defmodule Friends.Social.Note do
  use Ecto.Schema
  import Ecto.Changeset

  # Use existing friends_text_cards table from rzeczywiscie
  @derive {Jason.Encoder, only: [:id, :content, :user_id, :user_color, :user_name, :inserted_at]}
  schema "friends_text_cards" do
    field :user_id, :string
    field :user_color, :string
    field :user_name, :string
    field :content, :string

    belongs_to :room, Friends.Social.Room

    timestamps()
  end

  def changeset(note, attrs) do
    note
    |> cast(attrs, [:user_id, :user_color, :user_name, :content, :room_id])
    |> validate_required([:user_id, :content, :room_id])
    |> validate_length(:content, min: 1, max: 500)
  end
end

