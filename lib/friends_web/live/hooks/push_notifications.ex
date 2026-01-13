defmodule FriendsWeb.Live.Hooks.PushNotifications do
  import Phoenix.LiveView
  alias Friends.Accounts

  def on_mount(:default, _params, _session, socket) do
    {:cont, attach_hook(socket, :push_notifications, :handle_event, &handle_event/3)}
  end

  def handle_event("register_device_token", %{"token" => token, "platform" => platform}, socket) do
    if socket.assigns.current_user do
      Accounts.register_device_token(socket.assigns.current_user, token, platform)
    end
    {:noreply, socket}
  end

  def handle_event("push_notification_received", %{"title" => title, "body" => body}, socket) do
    # Trigger a flash message for foreground notifications
    {:noreply, put_flash(socket, :info, "#{title}: #{body}")}
  end

  def handle_event("push_notification_action", _payload, socket) do
    # Optional: Handle deep linking or specific actions
    {:noreply, socket}
  end

  def handle_event(_event, _params, socket), do: {:cont, socket}
end
