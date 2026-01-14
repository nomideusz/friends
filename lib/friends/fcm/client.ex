defmodule Friends.FCM.Client do
  @moduledoc """
  A direct HTTP client for Firebase Cloud Messaging (FCM) v1 API.
  Uses Hackney for requests and Goth for authentication.
  """
  require Logger

  @scope "https://www.googleapis.com/auth/firebase.messaging"

  def push(token, title, body, data \\ %{}) do
    case get_project_id() do
      nil -> 
        Logger.error("FCM: Project ID not found in configuration.")
        {:error, :no_project_id}
      project_id ->
        push_to_project(project_id, token, title, body, data)
    end
  end

  defp push_to_project(project_id, token, title, body, data) do
    url = "https://fcm.googleapis.com/v1/projects/#{project_id}/messages:send"
    
    with {:ok, auth_token} <- get_auth_token(),
         payload <- build_payload(token, title, body, data),
         headers <- [{"Authorization", "Bearer #{auth_token.token}"}, {"Content-Type", "application/json"}],
         {:ok, body_json} <- Jason.encode(payload) do
      
      Logger.info("FCM: Sending request to #{url} for token #{String.slice(token, 0, 10)}...")
      
      case :hackney.request(:post, url, headers, body_json, [:with_body]) do
        {:ok, 200, _headers, resp_body} ->
          Logger.info("FCM: Success! Response: #{resp_body}")
          {:ok, Jason.decode!(resp_body)}
          
        {:ok, status, _headers, resp_body} ->
          Logger.error("FCM: Request failed with status #{status}. Body: #{resp_body}")
          {:error, {:http_error, status, resp_body}}
          
        {:error, reason} ->
          Logger.error("FCM: HTTP request error: #{inspect(reason)}")
          {:error, reason}
      end
    else
      error ->
        Logger.error("FCM: Setup error: #{inspect(error)}")
        error
    end
  end

  defp get_auth_token do
    # Requires Goth to be running named Friends.FCM.Goth
    Goth.Token.fetch(Friends.FCM.Goth, @scope)
  end

  defp get_project_id do
    case Application.get_env(:friends, :fcm_service_account) do
      %{"project_id" => id} -> id
      _ -> nil
    end
  end

  defp build_payload(token, title, body, data) do
    %{
      "message" => %{
        "token" => token,
        "notification" => %{
          "title" => title,
          "body" => body
        },
        "data" => data
      }
    }
  end
end
