defmodule FriendsWeb.API.GraphController do
  @moduledoc """
  JSON API controller for social graph data.
  Returns nodes and links for 3D visualization.
  """
  use FriendsWeb, :controller

  alias Friends.Social

  @doc """
  GET /api/v1/graph - Get social graph for current user
  """
  def index(conn, _params) do
    case conn.assigns[:current_user] do
      nil ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Not authenticated"})

      user ->
        # Build graph data
        graph_data = build_graph_for_api(user)
        json(conn, graph_data)
    end
  end

  defp build_graph_for_api(user) do
    # list_friends returns maps with :user, :direction, :friendship keys
    friend_results = Social.list_friends(user.id)
    
    # Extract the actual user structs
    friends = Enum.map(friend_results, fn result -> 
      case result do
        %{user: friend_user} -> friend_user
        friend when is_struct(friend) -> friend
        _ -> nil
      end
    end) |> Enum.reject(&is_nil/1)
    
    friend_ids = Enum.map(friends, & &1.id)

    # Build nodes
    nodes = [
      # Current user as center node
      %{
        id: "user-#{user.id}",
        label: user.display_name || user.username,
        username: user.username,
        avatar: user.avatar_url,
        type: "current_user",
        x: 0,
        y: 0,
        z: 0
      }
      |
      # Friend nodes
      Enum.with_index(friends)
      |> Enum.map(fn {friend, idx} ->
        # Distribute friends in a circle around center
        angle = (idx / max(length(friends), 1)) * 2 * :math.pi()
        radius = 50

        %{
          id: "user-#{friend.id}",
          label: friend.display_name || friend.username,
          username: friend.username,
          avatar: friend.avatar_url,
          type: "friend",
          x: radius * :math.cos(angle),
          y: radius * :math.sin(angle),
          z: :rand.uniform() * 20 - 10
        }
      end)
    ]

    # Build links (connections between current user and friends)
    links = Enum.map(friends, fn friend ->
      %{
        source: "user-#{user.id}",
        target: "user-#{friend.id}",
        strength: 1.0
      }
    end)

    # Add inter-friend connections (friends who are also friends with each other)
    # OPTIMIZED: Single query instead of N queries
    inter_friend_links = build_inter_friend_links_optimized(friend_ids)

    %{
      nodes: nodes,
      links: links ++ inter_friend_links
    }
  end

  # Optimized version: single query to get all inter-friend connections
  defp build_inter_friend_links_optimized(friend_ids) when friend_ids == [], do: []
  defp build_inter_friend_links_optimized(friend_ids) do
    import Ecto.Query
    alias Friends.Repo
    alias Friends.Social.Friendship

    # Single query: find all friendships where BOTH users are in our friend list
    Repo.all(
      from f in Friendship,
        where: f.status == "accepted" and
               f.user_id in ^friend_ids and
               f.friend_user_id in ^friend_ids and
               f.user_id < f.friend_user_id,  # Dedupe: only one direction
        select: {f.user_id, f.friend_user_id}
    )
    |> Enum.map(fn {from_id, to_id} ->
      %{
        source: "user-#{from_id}",
        target: "user-#{to_id}",
        strength: 0.5
      }
    end)
  end
end
