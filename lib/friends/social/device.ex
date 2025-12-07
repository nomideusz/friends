defmodule Friends.Social.Device do
  use Ecto.Schema
  import Ecto.Changeset

  # Use existing friends_device_links table from rzeczywiscie
  schema "friends_device_links" do
    field :browser_id, :string
    field :fingerprint, :string, source: :device_fingerprint
    field :master_id, :string, source: :master_user_id
    field :user_name, :string
    
    belongs_to :user, Friends.Social.User

    timestamps()
  end

  def changeset(device, attrs) do
    device
    |> cast(attrs, [:browser_id, :fingerprint, :master_id, :user_name, :user_id])
    |> validate_required([:browser_id, :master_id])
    |> validate_length(:user_name, max: 20)
    |> unique_constraint(:browser_id)
  end
end

