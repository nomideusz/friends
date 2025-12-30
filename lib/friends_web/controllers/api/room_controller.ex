defmodule FriendsWeb.API.RoomController do
  @moduledoc """
  JSON API controller for rooms/groups.
  """
  use FriendsWeb, :controller

  alias Friends.Social

  @doc """
  GET /api/v1/rooms - Get user's rooms
  """
  def index(conn, _params) do
    case conn.assigns[:current_user] do
      nil ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Not authenticated"})

      user ->
        rooms = Social.list_user_rooms(user.id)

        json(conn, %{
          rooms: Enum.map(rooms, fn room ->
            %{
              id: room.id,
              code: room.code,
              name: room.name,
              type: room.room_type,
              is_private: room.is_private
            }
          end)
        })
    end
  end

  @doc """
  GET /api/v1/rooms/:id - Get room details with members
  """
  def show(conn, %{"id" => id}) do
    user = conn.assigns[:current_user]

    with room when not is_nil(room) <- Social.get_room(id),
         true <- Social.can_access_room?(room, user && user.id) do
      members = Social.list_room_members(room.id)

      json(conn, %{
        id: room.id,
        code: room.code,
        name: room.name,
        type: room.room_type,
        is_private: room.is_private,
        members: Enum.map(members, fn member ->
          %{
            id: member.user.id,
            username: member.user.username,
            display_name: member.user.display_name,
            avatar_url: member.user.avatar_url,
            role: member.role
          }
        end)
      })
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Room not found"})

      false ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Access denied"})
    end
  end

  @doc """
  GET /api/v1/rooms/:id/messages - Get room messages
  """
  def messages(conn, %{"id" => id}) do
    user = conn.assigns[:current_user]
    limit = conn.params["limit"] || 50

    with room when not is_nil(room) <- Social.get_room(id),
         true <- Social.can_access_room?(room, user && user.id) do
      messages = Social.list_room_messages(room.id, limit)

      json(conn, %{
        messages: Enum.map(messages, fn msg ->
          %{
            id: msg.id,
            sender_id: msg.sender_id,
            content: msg.content,
            type: msg.type,
            metadata: msg.metadata,
            inserted_at: msg.inserted_at
          }
        end)
      })
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Room not found"})

      false ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Access denied"})
    end
  end
end
