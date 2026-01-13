defmodule Friends.Social.Notification do
  @moduledoc """
  Schema for persistent user notifications.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "friends_notifications" do
    belongs_to :user, Friends.Social.User
    field :type, :string  # message, friend_request, trust_request, group_invite, connection_accepted, trust_confirmed
    field :read, :boolean, default: false

    # Actor info
    belongs_to :actor, Friends.Social.User
    field :actor_username, :string
    field :actor_color, :string
    field :actor_avatar_url, :string

    # Context info
    belongs_to :room, Friends.Social.Room
    field :room_code, :string
    field :room_name, :string
    belongs_to :conversation, Friends.Social.Conversation

    # Display content
    field :text, :string
    field :preview, :string

    # Grouping
    field :group_key, :string
    field :count, :integer, default: 1

    timestamps()
  end

  @required_fields [:user_id, :type, :text]
  @optional_fields [
    :read, :actor_id, :actor_username, :actor_color, :actor_avatar_url,
    :room_id, :room_code, :room_name, :conversation_id,
    :preview, :group_key, :count
  ]

  def changeset(notification, attrs) do
    notification
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:type, ~w(message friend_request trust_request group_invite connection_accepted trust_confirmed))
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:actor_id)
    |> foreign_key_constraint(:room_id)
    |> foreign_key_constraint(:conversation_id)
  end

  @doc """
  Convert a notification struct to a map suitable for UI display.
  """
  def to_display_map(%__MODULE__{} = notification) do
    %{
      id: notification.id,
      type: String.to_atom(notification.type),
      timestamp: notification.inserted_at,
      read: notification.read,
      actor_id: notification.actor_id,
      actor_username: notification.actor_username,
      actor_color: notification.actor_color || "#6B7280",
      actor_avatar_url: notification.actor_avatar_url,
      room_id: notification.room_id,
      room_code: notification.room_code,
      room_name: notification.room_name,
      conversation_id: notification.conversation_id,
      text: notification.text,
      preview: notification.preview,
      group_key: notification.group_key,
      count: notification.count || 1
    }
  end
end
