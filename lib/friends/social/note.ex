defmodule Friends.Social.Note do
  use Ecto.Schema
  import Ecto.Changeset

  @grace_period_minutes 15

  # Use existing friends_text_cards table from rzeczywiscie
  @derive {Jason.Encoder,
           only: [:id, :content, :user_id, :user_color, :user_name, :inserted_at, :editable_until]}
  schema "friends_text_cards" do
    field :user_id, :string
    field :user_color, :string
    field :user_name, :string
    field :content, :string
    field :editable_until, :utc_datetime_usec

    belongs_to :room, Friends.Social.Room

    timestamps()
  end

  def changeset(note, attrs) do
    note
    |> cast(attrs, [:user_id, :user_color, :user_name, :content, :room_id, :editable_until])
    |> validate_required([:user_id, :content, :room_id])
    |> validate_length(:content, min: 1, max: 500)
    |> maybe_set_editable_until()
  end

  @doc """
  Changeset for public notes (no room_id required).
  """
  def public_changeset(note, attrs) do
    note
    |> cast(attrs, [:user_id, :user_color, :user_name, :content, :room_id, :editable_until])
    |> validate_required([:user_id, :content])
    |> validate_length(:content, min: 1, max: 500)
    |> maybe_set_editable_until()
  end

  defp maybe_set_editable_until(changeset) do
    # Only set editable_until for new notes (no id yet)
    if get_field(changeset, :id) == nil and get_field(changeset, :editable_until) == nil do
      editable_until = DateTime.utc_now() |> DateTime.add(@grace_period_minutes * 60, :second)
      put_change(changeset, :editable_until, editable_until)
    else
      changeset
    end
  end

  @doc """
  Check if a note is still within its edit grace period.
  """
  def editable?(%__MODULE__{editable_until: nil}), do: false

  def editable?(%__MODULE__{editable_until: until}) do
    DateTime.compare(DateTime.utc_now(), until) == :lt
  end

  def grace_period_minutes, do: @grace_period_minutes
end
