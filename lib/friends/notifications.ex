defmodule Friends.Notifications do
  @moduledoc """
  Handles sending push notifications to devices.
  """
  
  import Ecto.Query, warn: false
  alias Friends.Repo
  alias Friends.Accounts
  alias Friends.Accounts.DeviceToken
  require Logger
  
  # Using Pigeon for APNS/FCM
  # Ensure you have configured Pigeon in config.exs
  
  def send_to_user(user_id, title, body, data \\ %{}) do
    Logger.info("Notifications: Attempting to send push to user #{user_id} (title: #{title})")
    tokens = Accounts.list_user_device_tokens(user_id)
    
    # Check if we have valid tokens
    if Enum.empty?(tokens) do
      Logger.info("Notifications: No device tokens found for user #{user_id}")
      {:error, :no_tokens}
    else
      results = Enum.map(tokens, fn token ->
        send_to_token(token, title, body, data)
      end)
      
      {:ok, results}
    end
  end
  
  defp send_to_token(%DeviceToken{platform: "android", token: token}, title, body, data) do
    # FCM
    # FCM
    n = Pigeon.FCM.Notification.new({:token, token}, %{
      "title" => title, 
      "body" => body
    }, data)
    
    # Pigeon.FCM.push(n)
    result = Pigeon.FCM.push(n)
    Logger.info("Notifications: Sent FCM to token #{String.slice(token, 0, 10)}... Result: #{inspect(result)}")
    result
  end
  
  defp send_to_token(%DeviceToken{platform: "ios", token: token}, title, body, data) do
    # APNS
    n = Pigeon.APNS.Notification.new(body, token, title)
    |> Pigeon.APNS.Notification.put_custom(data)
    
    # Pigeon.APNS.push(n)
    IO.puts("Would send APNS to #{token}: #{title}")
    {:ok, :sent_mock}
  end
  
  defp send_to_token(_, _, _, _), do: {:error, :unknown_platform}
end
