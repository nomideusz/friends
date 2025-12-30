defmodule FriendsWeb.API.UserController do
  @moduledoc """
  JSON API controller for user data.
  """
  use FriendsWeb, :controller

  alias Friends.Social

  @doc """
  GET /api/v1/me - Get current authenticated user
  """
  def me(conn, _params) do
    case conn.assigns[:current_user] do
      nil ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Not authenticated"})

      user ->
        json(conn, %{
          id: user.id,
          username: user.username,
          display_name: user.display_name,
          avatar_url: user.avatar_url,
          status: user.status
        })
    end
  end

  @doc """
  GET /api/v1/users/:id - Get user by ID
  """
  def show(conn, %{"id" => id}) do
    case Social.get_user(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "User not found"})

      user ->
        json(conn, %{
          id: user.id,
          username: user.username,
          display_name: user.display_name,
          avatar_url: user.avatar_url
        })
    end
  end

  @doc """
  GET /api/v1/users/search?q=query - Search users
  """
  def search(conn, %{"q" => query}) do
    users = Social.search_users(query, limit: 20)

    json(conn, %{
      users: Enum.map(users, fn user ->
        %{
          id: user.id,
          username: user.username,
          display_name: user.display_name,
          avatar_url: Map.get(user, :avatar_url)
        }
      end)
    })
  end

  def search(conn, _params) do
    json(conn, %{users: []})
  end

  @doc """
  GET /api/v1/friends - Get current user's friends
  """
  def friends(conn, _params) do
    case conn.assigns[:current_user] do
      nil ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Not authenticated"})

      user ->
        friend_results = Social.list_friends(user.id)
        
        # Extract actual user structs from friendship results
        friends = Enum.map(friend_results, fn result ->
          case result do
            %{user: friend_user} -> friend_user
            friend when is_struct(friend) -> friend
            _ -> nil
          end
        end) |> Enum.reject(&is_nil/1)

        json(conn, %{
          friends: Enum.map(friends, fn friend ->
            %{
              id: friend.id,
              username: friend.username,
              display_name: friend.display_name,
              avatar_url: friend.avatar_url
            }
          end)
        })
    end
  end
end
