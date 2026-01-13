defmodule Friends.Accounts.DeviceToken do
  use Ecto.Schema
  import Ecto.Changeset

  schema "device_tokens" do
    field :token, :string
    field :platform, :string # "android" or "ios"
    belongs_to :user, Friends.Social.User

    timestamps()
  end

  @doc false
  def changeset(device_token, attrs) do
    device_token
    |> cast(attrs, [:token, :platform, :user_id])
    |> validate_required([:token, :platform, :user_id])
    |> unique_constraint([:token, :user_id])
  end
end
