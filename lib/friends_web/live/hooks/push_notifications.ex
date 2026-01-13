defmodule FriendsWeb.Live.Hooks.PushNotifications do
  import Phoenix.LiveView
  alias Friends.Accounts
  require Logger

  def on_mount(:default, _params, _session, socket) do
    {:cont, attach_hook(socket, :push_notifications, :handle_event, &handle_event/3)}
  end

  def handle_event("register_device_token", %{"token" => token, "platform" => platform}, socket) do
    Logger.info("PushNotifications hook: Registering device token for user #{socket.assigns.current_user.id}: #{String.slice(token, 0, 10)}... (platform: #{platform})")
    if socket.assigns.current_user do
      Accounts.register_device_token(socket.assigns.current_user, token, platform)
    end
    {:halt, socket}
  end

  def handle_event("push_notification_received", %{"title" => title, "body" => body}, socket) do
    # Trigger a flash message for foreground notifications
    {:halt, put_flash(socket, :info, "#{title}: #{body}")}
  end

  def handle_event("push_notification_action", _payload, socket) do
    # Optional: Handle deep linking or specific actions
    {:halt, socket}
  end

  def handle_event(_event, _params, socket), do: {:cont, socket}
end
