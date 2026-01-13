defmodule Friends.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Friends.Repo

  alias Friends.Accounts.DeviceToken
  alias Friends.Social.User

  @doc """
  Registers a device token for a user.
  If the token already exists for the user, update the timestamp.
  """
  def register_device_token(%User{} = user, token, platform) when platform in ["android", "ios"] do
    # Check if token exists
    case Repo.get_by(DeviceToken, token: token) do
      nil ->
        %DeviceToken{}
        |> DeviceToken.changeset(%{
          user_id: user.id,
          token: token,
          platform: platform
        })
        |> Repo.insert()

      %DeviceToken{user_id: user_id} = existing_token ->
        if user_id == user.id do
          {:ok, existing_token}
        else
          # Token belongs to another user (maybe switched accounts on same device)
          # Update ownership
          existing_token
          |> DeviceToken.changeset(%{user_id: user.id})
          |> Repo.update()
        end
    end
  end

  @doc """
  Gets all device tokens for a user.
  """
  def list_user_device_tokens(user_id) do
    Repo.all(from d in DeviceToken, where: d.user_id == ^user_id)
  end
end
