defmodule FriendsWeb.HomeLive.Events.NotificationEvents do
  @moduledoc """
  Event handlers for the unified notification system.
  Supports message notifications, friend requests, trust requests, group invites, and more.
  Notifications are persisted to database for cross-session access.
  Also triggers push notifications to mobile devices.
  """
  import Phoenix.Component
  import Phoenix.LiveView
  alias Friends.Social.Notifications
  alias Friends.Social.Presence
  alias Friends.Notifications, as: PushNotifications
  use FriendsWeb, :verified_routes

  @doc """
  Add a notification to the database and update socket assigns.
  Also sends push notification to mobile devices if user is offline.
  Returns the updated socket.
  """
  def add_notification(socket, notification_attrs, user_id) do
    # Convert atom type to string for database
    db_attrs = notification_attrs
    |> Map.put(:type, to_string(notification_attrs.type))
    |> Map.put(:user_id, user_id)
    |> Map.delete(:id)
    |> Map.delete(:timestamp)

    case Notifications.create_notification(db_attrs) do
      {:ok, _notification} ->
        # Send push notification if user is not currently online
        maybe_send_push_notification(user_id, notification_attrs)
        # Reload notifications from database to get correct state
        reload_notifications(socket, user_id)

      {:error, _} ->
        # If DB insert fails, still update in-memory for this session
        add_notification_in_memory(socket, notification_attrs)
    end
  end

  @doc """
  Add notification to in-memory list only (fallback if no user_id).
  """
  def add_notification_in_memory(socket, notification) do
    notifications = socket.assigns[:notifications] || []

    notifications =
      case find_groupable(notifications, notification) do
        nil ->
          [notification | notifications] |> Enum.take(50)

        {index, existing} ->
          updated = %{existing | count: existing.count + 1, timestamp: notification.timestamp}
          List.replace_at(notifications, index, updated)
      end

    unread_count = Enum.count(notifications, & !&1.read)

    socket
    |> assign(:notifications, notifications)
    |> assign(:notifications_unread_count, unread_count)
  end

  @doc """
  Reload notifications from database.
  """
  def reload_notifications(socket, user_id) do
    notifications = Notifications.list_notifications(user_id)
    unread_count = Notifications.count_unread(user_id)

    socket
    |> assign(:notifications, notifications)
    |> assign(:notifications_unread_count, unread_count)
  end

  @doc """
  Toggle the expanded state of the notification tray.
  """
  def toggle_tray(socket) do
    {:noreply, assign(socket, :notifications_expanded, !socket.assigns.notifications_expanded)}
  end

  @doc """
  View a notification - marks as read and navigates to context.
  """
  def view_notification(socket, notification_id) do
    notifications = socket.assigns[:notifications] || []

    # Try to parse as integer (database ID) or use as-is (in-memory ID)
    parsed_id = case Integer.parse(to_string(notification_id)) do
      {int_id, ""} -> int_id
      _ -> notification_id
    end

    case Enum.find(notifications, fn n -> n.id == parsed_id || n.id == notification_id end) do
      nil ->
        {:noreply, socket}

      notification ->
        # Mark as read in database
        if is_integer(parsed_id) do
          Notifications.mark_read(parsed_id)
        end

        # Update in-memory state
        updated_notifications =
          Enum.map(notifications, fn n ->
            if n.id == parsed_id || n.id == notification_id do
              %{n | read: true}
            else
              n
            end
          end)

        unread_count = Enum.count(updated_notifications, & !&1.read)

        socket =
          socket
          |> assign(:notifications, updated_notifications)
          |> assign(:notifications_unread_count, unread_count)
          |> assign(:notifications_expanded, false)

        # Navigate based on notification type
        navigate_to_notification(socket, notification)
    end
  end

  @doc """
  Dismiss a single notification.
  """
  def dismiss_notification(socket, notification_id) do
    notifications = socket.assigns[:notifications] || []

    # Try to parse as integer (database ID)
    parsed_id = case Integer.parse(to_string(notification_id)) do
      {int_id, ""} -> int_id
      _ -> notification_id
    end

    # Delete from database
    if is_integer(parsed_id) do
      Notifications.delete_notification(parsed_id)
    end

    # Update in-memory state
    updated = Enum.reject(notifications, fn n -> n.id == parsed_id || n.id == notification_id end)
    unread_count = Enum.count(updated, & !&1.read)

    {:noreply,
     socket
     |> assign(:notifications, updated)
     |> assign(:notifications_unread_count, unread_count)}
  end

  @doc """
  Clear all notifications.
  """
  def clear_all_notifications(socket) do
    user_id = socket.assigns[:current_user] && socket.assigns.current_user.id

    # Delete from database
    if user_id do
      Notifications.clear_all(user_id)
    end

    {:noreply,
     socket
     |> assign(:notifications, [])
     |> assign(:notifications_unread_count, 0)
     |> assign(:notifications_expanded, false)}
  end

  # --- Notification Builders ---

  @doc """
  Build a notification from various event types.
  Supports :message, :friend_request, :trust_request, :group_invite, :connection_accepted, :trust_confirmed.
  """
  def build_notification(type, data, extra \\ nil)

  def build_notification(:message, message, room) do
    sender = message.sender
    %{
      type: :message,
      read: false,
      actor_id: sender.id,
      actor_username: sender.username,
      actor_color: sender.user_color || "#6B7280",
      actor_avatar_url: sender.avatar_url_thumb,
      room_id: room.id,
      room_code: room.code,
      room_name: room.name,
      conversation_id: message.conversation_id,
      text: message_text(message.content_type),
      preview: nil,
      group_key: "messages:room:#{room.id}",
      count: 1
    }
  end

  def build_notification(:friend_request, from_user, _extra) do
    %{
      type: :friend_request,
      read: false,
      actor_id: from_user.id,
      actor_username: from_user.username,
      actor_color: from_user.user_color || "#6B7280",
      actor_avatar_url: Map.get(from_user, :avatar_url_thumb),
      room_id: nil,
      room_code: nil,
      room_name: nil,
      conversation_id: nil,
      text: "wants to connect",
      preview: nil,
      group_key: nil,
      count: 1
    }
  end

  def build_notification(:trust_request, from_user, _extra) do
    %{
      type: :trust_request,
      read: false,
      actor_id: from_user.id,
      actor_username: from_user.username,
      actor_color: from_user.user_color || "#6B7280",
      actor_avatar_url: Map.get(from_user, :avatar_url_thumb),
      room_id: nil,
      room_code: nil,
      room_name: nil,
      conversation_id: nil,
      text: "wants you as recovery contact",
      preview: nil,
      group_key: nil,
      count: 1
    }
  end

  def build_notification(:group_invite, invite_info, _extra) do
    %{
      type: :group_invite,
      read: false,
      actor_id: invite_info[:inviter_id],
      actor_username: invite_info.inviter_username,
      actor_color: invite_info[:inviter_color] || "#6B7280",
      actor_avatar_url: nil,
      room_id: nil,
      room_code: invite_info.room_code,
      room_name: invite_info.room_name,
      conversation_id: nil,
      text: "invited you to #{invite_info.room_name || "a group"}",
      preview: nil,
      group_key: nil,
      count: 1
    }
  end

  def build_notification(:connection_accepted, by_user, _extra) do
    %{
      type: :connection_accepted,
      read: false,
      actor_id: by_user.id,
      actor_username: by_user.username,
      actor_color: by_user.user_color || "#6B7280",
      actor_avatar_url: Map.get(by_user, :avatar_url_thumb),
      room_id: nil,
      room_code: nil,
      room_name: nil,
      conversation_id: nil,
      text: "accepted your connection",
      preview: nil,
      group_key: nil,
      count: 1
    }
  end

  def build_notification(:trust_confirmed, by_user, _extra) do
    %{
      type: :trust_confirmed,
      read: false,
      actor_id: by_user.id,
      actor_username: by_user.username,
      actor_color: by_user.user_color || "#6B7280",
      actor_avatar_url: Map.get(by_user, :avatar_url_thumb),
      room_id: nil,
      room_code: nil,
      room_name: nil,
      conversation_id: nil,
      text: "confirmed as your recovery contact",
      preview: nil,
      group_key: nil,
      count: 1
    }
  end

  # --- Private Helpers ---

  defp find_groupable(notifications, new_notification) do
    if new_notification[:group_key] do
      notifications
      |> Enum.with_index()
      |> Enum.find(fn {n, _idx} ->
        n[:group_key] == new_notification[:group_key] &&
        n[:timestamp] &&
        DateTime.diff(DateTime.utc_now(), n.timestamp, :minute) < 30
      end)
      |> case do
        {existing, index} -> {index, existing}
        nil -> nil
      end
    else
      nil
    end
  end

  defp navigate_to_notification(socket, notification) do
    case notification.type do
      type when type in [:message, "message"] ->
        if notification.room_code do
          {:noreply, push_navigate(socket, to: ~p"/r/#{notification.room_code}?action=chat")}
        else
          {:noreply, socket}
        end

      type when type in [:friend_request, "friend_request"] ->
        {:noreply,
         socket
         |> assign(:show_people_modal, true)
         |> assign(:contact_mode, :pending)}

      type when type in [:trust_request, "trust_request"] ->
        {:noreply,
         socket
         |> assign(:show_profile_sheet, true)
         |> assign(:settings_tab, "recovery")}

      type when type in [:group_invite, "group_invite"] ->
        if notification.room_code do
          {:noreply, push_navigate(socket, to: ~p"/r/#{notification.room_code}")}
        else
          {:noreply, socket}
        end

      type when type in [:connection_accepted, "connection_accepted"] ->
        {:noreply, assign(socket, :show_people_modal, true)}

      type when type in [:trust_confirmed, "trust_confirmed"] ->
        {:noreply,
         socket
         |> assign(:show_profile_sheet, true)
         |> assign(:settings_tab, "recovery")}

      _ ->
        {:noreply, socket}
    end
  end

  defp message_text("text"), do: "sent a message"
  defp message_text("voice"), do: "sent a voice message"
  defp message_text("image"), do: "sent a photo"
  defp message_text(_), do: "sent a message"

  # --- Push Notifications ---

  defp maybe_send_push_notification(user_id, notification_attrs) do
    # Only send push if user is not currently online (has no active presence)
    unless Presence.online?(user_id) do
      send_push_notification(user_id, notification_attrs)
    end
  end

  defp send_push_notification(user_id, notification_attrs) do
    actor_username = notification_attrs[:actor_username] || "Someone"
    text = notification_attrs[:text] || "sent you a notification"
    type = notification_attrs[:type]

    title = push_title(type, actor_username)
    body = push_body(type, actor_username, text, notification_attrs)

    # Build data payload for navigation when notification is tapped
    data = %{
      type: to_string(type),
      actor_id: notification_attrs[:actor_id],
      room_code: notification_attrs[:room_code],
      conversation_id: notification_attrs[:conversation_id]
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()

    # Send via Pigeon (FCM/APNS)
    Task.start(fn ->
      PushNotifications.send_to_user(user_id, title, body, data)
    end)
  end

  defp push_title(:message, actor), do: "New message from @#{actor}"
  defp push_title(:friend_request, actor), do: "@#{actor} wants to connect"
  defp push_title(:trust_request, actor), do: "@#{actor} wants you as recovery contact"
  defp push_title(:group_invite, actor), do: "@#{actor} invited you to a group"
  defp push_title(:connection_accepted, actor), do: "@#{actor} accepted your connection"
  defp push_title(:trust_confirmed, actor), do: "@#{actor} confirmed as recovery contact"
  defp push_title(_, actor), do: "Notification from @#{actor}"

  defp push_body(:message, _actor, _text, attrs) do
    room_name = attrs[:room_name]
    if room_name, do: "In #{room_name}", else: "Tap to view"
  end
  defp push_body(:group_invite, _actor, _text, attrs) do
    room_name = attrs[:room_name]
    if room_name, do: "Join #{room_name}", else: "Tap to view invitation"
  end
  defp push_body(_type, _actor, text, _attrs), do: text
end
