defmodule Friends.Social.Notifications do
  @moduledoc """
  Functions for managing user notifications.
  """
  import Ecto.Query
  alias Friends.Repo
  alias Friends.Social.Notification

  @max_notifications 50

  @doc """
  List notifications for a user, ordered by most recent first.
  """
  def list_notifications(user_id, limit \\ @max_notifications) do
    Notification
    |> where([n], n.user_id == ^user_id)
    |> order_by([n], desc: n.inserted_at)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&Notification.to_display_map/1)
  end

  @doc """
  Count unread notifications for a user.
  """
  def count_unread(user_id) do
    Notification
    |> where([n], n.user_id == ^user_id and n.read == false)
    |> Repo.aggregate(:count)
  end

  @doc """
  Create a notification, with optional grouping.
  If a notification with the same group_key exists within 30 minutes, increment its count instead.
  """
  def create_notification(attrs) do
    group_key = attrs[:group_key]
    user_id = attrs[:user_id]

    if group_key && user_id do
      # Check for existing groupable notification
      thirty_mins_ago = DateTime.add(DateTime.utc_now(), -30, :minute)

      existing =
        Notification
        |> where([n], n.user_id == ^user_id and n.group_key == ^group_key)
        |> where([n], n.inserted_at > ^thirty_mins_ago)
        |> order_by([n], desc: n.inserted_at)
        |> limit(1)
        |> Repo.one()

      if existing do
        # Increment count and update timestamp
        existing
        |> Ecto.Changeset.change(%{count: existing.count + 1, read: false})
        |> Repo.update()
      else
        create_new_notification(attrs)
      end
    else
      create_new_notification(attrs)
    end
  end

  defp create_new_notification(attrs) do
    user_id = attrs[:user_id]

    # Enforce max notifications limit - delete oldest if at limit
    count = Notification |> where([n], n.user_id == ^user_id) |> Repo.aggregate(:count)

    if count >= @max_notifications do
      # Delete oldest notifications to make room
      oldest =
        Notification
        |> where([n], n.user_id == ^user_id)
        |> order_by([n], asc: n.inserted_at)
        |> limit(^(count - @max_notifications + 1))
        |> Repo.all()

      Enum.each(oldest, &Repo.delete/1)
    end

    %Notification{}
    |> Notification.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Mark a notification as read.
  """
  def mark_read(notification_id) do
    case Repo.get(Notification, notification_id) do
      nil -> {:error, :not_found}
      notification ->
        notification
        |> Ecto.Changeset.change(%{read: true})
        |> Repo.update()
    end
  end

  @doc """
  Mark all notifications for a user as read.
  """
  def mark_all_read(user_id) do
    Notification
    |> where([n], n.user_id == ^user_id and n.read == false)
    |> Repo.update_all(set: [read: true])
  end

  @doc """
  Delete a notification.
  """
  def delete_notification(notification_id) do
    case Repo.get(Notification, notification_id) do
      nil -> {:error, :not_found}
      notification -> Repo.delete(notification)
    end
  end

  @doc """
  Delete all notifications for a user.
  """
  def clear_all(user_id) do
    Notification
    |> where([n], n.user_id == ^user_id)
    |> Repo.delete_all()
  end

  @doc """
  Get a notification by ID.
  """
  def get_notification(id) do
    case Repo.get(Notification, id) do
      nil -> nil
      notification -> Notification.to_display_map(notification)
    end
  end
end
