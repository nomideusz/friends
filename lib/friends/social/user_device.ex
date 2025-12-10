defmodule Friends.Social.UserDevice do
  use Ecto.Schema
  import Ecto.Changeset

  schema "friends_user_devices" do
    field :device_fingerprint, :string
    field :device_name, :string
    field :public_key_fingerprint, :string
    field :last_seen_at, :utc_datetime
    field :first_seen_at, :utc_datetime
    field :trusted, :boolean, default: true
    field :revoked, :boolean, default: false

    belongs_to :user, Friends.Social.User

    timestamps()
  end

  def changeset(device, attrs) do
    device
    |> cast(attrs, [
      :user_id,
      :device_fingerprint,
      :device_name,
      :public_key_fingerprint,
      :last_seen_at,
      :first_seen_at,
      :trusted,
      :revoked
    ])
    |> validate_required([:user_id, :device_fingerprint])
  end
end
