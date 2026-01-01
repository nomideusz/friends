defmodule FriendsWeb.HomeLive.GraphHelper do
  @moduledoc """
  Helper module for building network graph data.
  Shared between HomeLive and NetworkLive.
  """
  alias Friends.Social
  alias Friends.Repo
  import Ecto.Query

  @colors ~w(#ef4444 #f97316 #eab308 #22c55e #14b8a6 #3b82f6 #8b5cf6 #ec4899)

  @doc """
  Builds graph data for a user's social network.
  Returns a map with nodes, edges, and stats.
  """
  def build_graph_data(nil), do: nil
  def build_graph_data(user) do
    user_id = user.id

    # 1. People I trust (confirmed)
    my_trusted = Social.list_trusted_friends(user_id)

    # 2. People who trust me (confirmed) - reverse relationships
    people_who_trust_me =
      Repo.all(
        from tf in Friends.Social.TrustedFriend,
          where: tf.trusted_user_id == ^user_id and tf.status == "confirmed",
          preload: [:user]
      )

    # 3. My friends (accepted)
    friends = Social.list_friends(user_id)
    friend_ids = Enum.map(friends, fn f -> f.user.id end)

    # 4. Get friendships BETWEEN my friends
    friend_to_friend_edges = get_friendships_between(friend_ids)

    # 5. Get friends of friends (2nd degree connections)
    {second_degree_friends, second_degree_edges} = get_second_degree_connections(friend_ids, user_id)

    # Build nodes map
    nodes_map = %{}

    # Add current user as central node
    current_user_node = %{
      id: user.id,
      username: user.username,
      display_name: user.display_name,
      color: user_color(user),
      type: "self",
      connected_at: user.inserted_at
    }

    nodes_map = Map.put(nodes_map, user.id, current_user_node)

    # Add trusted users
    nodes_map =
      Enum.reduce(my_trusted, nodes_map, fn tf, acc ->
        Map.put(acc, tf.trusted_user.id, %{
          id: tf.trusted_user.id,
          username: tf.trusted_user.username,
          display_name: tf.trusted_user.display_name,
          color: user_color(tf.trusted_user),
          type: "trusted",
          connected_at: tf.inserted_at
        })
      end)

    # Add people who trust me
    nodes_map =
      Enum.reduce(people_who_trust_me, nodes_map, fn tf, acc ->
        Map.update(acc, tf.user.id,
          %{
            id: tf.user.id,
            username: tf.user.username,
            display_name: tf.user.display_name,
            color: user_color(tf.user),
            type: "trusts_me",
            connected_at: tf.inserted_at
          },
          fn existing -> existing end
        )
      end)

    # Add social friends (with mutual count)
    nodes_map =
      Enum.reduce(friends, nodes_map, fn f, acc ->
        mutual_count = count_mutual_friends(user_id, f.user.id)
        
        Map.update(acc, f.user.id,
          %{
            id: f.user.id,
            username: f.user.username,
            display_name: f.user.display_name,
            color: user_color(f.user),
            type: "friend",
            mutual_count: mutual_count,
            connected_at: f.friendship.accepted_at
          },
          fn existing -> 
            Map.put(existing, :mutual_count, mutual_count)
          end
        )
      end)

    # Add second degree connections
    nodes_map =
      Enum.reduce(second_degree_friends, nodes_map, fn friend, acc ->
        Map.put_new(acc, friend.id, %{
          id: friend.id,
          username: friend.username,
          display_name: friend.display_name,
          color: user_color(friend),
          type: "second_degree",
          connected_at: user.inserted_at
        })
      end)

    # Build edges
    edges = []

    # Edges for people I trust
    edges =
      Enum.reduce(my_trusted, edges, fn tf, acc ->
        [%{from: user.id, to: tf.trusted_user.id, type: "trusted", connected_at: tf.inserted_at} | acc]
      end)

    # Edges for people who trust me
    edges =
      Enum.reduce(people_who_trust_me, edges, fn tf, acc ->
        has_reverse = Enum.any?(my_trusted, fn t -> t.trusted_user.id == tf.user.id end)
        if has_reverse do
          acc
        else
          [%{from: tf.user.id, to: user.id, type: "trusts_me", connected_at: tf.inserted_at} | acc]
        end
      end)

    # Edges for my direct friends
    edges =
      Enum.reduce(friends, edges, fn f, acc ->
        mutual_count = count_mutual_friends(user_id, f.user.id)
        [%{from: user.id, to: f.user.id, type: "friend", mutual_count: mutual_count, connected_at: f.friendship.accepted_at} | acc]
      end)

    # Edges between my friends
    edges =
      Enum.reduce(friend_to_friend_edges, edges, fn {id1, id2}, acc ->
        [%{from: id1, to: id2, type: "mutual", connected_at: NaiveDateTime.utc_now()} | acc]
      end)

    # Add second degree edges
    edges = edges ++ second_degree_edges

    # Stats
    mutual_count =
      Enum.count(my_trusted, fn tf ->
        Enum.any?(people_who_trust_me, fn ptm -> ptm.user.id == tf.trusted_user.id end)
      end)

    %{
      current_user: current_user_node,
      nodes: Map.values(nodes_map) |> Enum.uniq_by(& &1.id),
      edges: edges,
      stats: %{
        total_connections: map_size(nodes_map) - 1,
        mutual_friends: mutual_count,
        i_trust: length(my_trusted),
        trust_me: length(people_who_trust_me),
        friends: length(friends),
        friend_connections: length(friend_to_friend_edges),
        second_degree: length(second_degree_friends),
        pending_in: 0,
        invited: 0
      }
    }
  end

  def user_color(%{id: id}) when is_integer(id) do
    Enum.at(@colors, rem(id, length(@colors)))
  end
  def user_color(_), do: Enum.at(@colors, 0)

  defp get_friendships_between(user_ids) when length(user_ids) < 2, do: []
  defp get_friendships_between(user_ids) do
    Repo.all(
      from f in Friends.Social.Friendship,
        where:
          f.user_id in ^user_ids and f.friend_user_id in ^user_ids and f.status == "accepted",
        select: {f.user_id, f.friend_user_id}
    )
    |> Enum.map(fn {id1, id2} ->
      if id1 < id2, do: {id1, id2}, else: {id2, id1}
    end)
    |> Enum.uniq()
  end

  defp get_second_degree_connections(friend_ids, _user_id) when length(friend_ids) == 0 do
    {[], []}
  end
  defp get_second_degree_connections(friend_ids, user_id) do
    friends_of_friends_1 =
      Repo.all(
        from f in Friends.Social.Friendship,
          where: f.user_id in ^friend_ids and f.status == "accepted",
          preload: [:friend_user]
      )
      |> Enum.map(fn f ->
        %{friend_id: f.friend_user_id, connector_id: f.user_id, friend_user: f.friend_user}
      end)

    friends_of_friends_2 =
      Repo.all(
        from f in Friends.Social.Friendship,
          where: f.friend_user_id in ^friend_ids and f.status == "accepted",
          preload: [:user]
      )
      |> Enum.map(fn f ->
        %{friend_id: f.user_id, connector_id: f.friend_user_id, friend_user: f.user}
      end)

    all_friends_of_friends = friends_of_friends_1 ++ friends_of_friends_2
    existing_ids = MapSet.new([user_id | friend_ids])

    second_degree_map =
      all_friends_of_friends
      |> Enum.reduce(%{}, fn friendship, acc ->
        friend_of_friend = friendship.friend_user
        if MapSet.member?(existing_ids, friendship.friend_id) do
          acc
        else
          Map.update(
            acc,
            friendship.friend_id,
            %{user: friend_of_friend, connections: [friendship.connector_id]},
            fn existing ->
              %{existing | connections: [friendship.connector_id | existing.connections]}
            end
          )
        end
      end)

    edges =
      second_degree_map
      |> Enum.flat_map(fn {second_degree_id, data} ->
        Enum.map(data.connections, fn friend_id ->
          %{from: friend_id, to: second_degree_id, type: "second_degree", connected_at: NaiveDateTime.utc_now()}
        end)
      end)

    second_degree_users =
      second_degree_map
      |> Map.values()
      |> Enum.map(fn data -> data.user end)

    {second_degree_users, edges}
  end

  defp count_mutual_friends(user_id1, user_id2) do
    friends1_as_user =
      Repo.all(
        from f in Friends.Social.Friendship,
          where: f.user_id == ^user_id1 and f.status == "accepted",
          select: f.friend_user_id
      )

    friends1_as_friend =
      Repo.all(
        from f in Friends.Social.Friendship,
          where: f.friend_user_id == ^user_id1 and f.status == "accepted",
          select: f.user_id
      )

    friends1_ids = MapSet.new(friends1_as_user ++ friends1_as_friend)

    friends2_as_user =
      Repo.all(
        from f in Friends.Social.Friendship,
          where: f.user_id == ^user_id2 and f.status == "accepted",
          select: f.friend_user_id
      )

    friends2_as_friend =
      Repo.all(
        from f in Friends.Social.Friendship,
          where: f.friend_user_id == ^user_id2 and f.status == "accepted",
          select: f.user_id
      )

    friends2_ids = MapSet.new(friends2_as_user ++ friends2_as_friend)

    MapSet.intersection(friends1_ids, friends2_ids)
    |> MapSet.size()
  end

  @doc """
  Builds constellation data for users with 0 connections.
  Shows discoverable users orbiting around the central self node.
  """
  def build_constellation_data(nil), do: nil
  def build_constellation_data(user) do
    discoverable = Social.list_discoverable_users(user.id, 30)

    %{
      self: %{
        id: user.id,
        username: user.username,
        display_name: user.display_name || user.username,
        color: user_color(user)
      },
      others: Enum.map(discoverable, fn u ->
        %{
          id: u.id,
          username: u.username,
          display_name: u.display_name || u.username,
          joined_at: u.inserted_at,
          color: Enum.at(@colors, rem(u.id, length(@colors)))
        }
      end)
    }
  end

  @doc """
  Builds global network data for the welcome screen.
  Fetches a sample of recent users and their mutual connections.
  """
  def build_welcome_graph_data do
    # Get sample of active users (reduced from 300 to 100 for performance)
    users =
      Repo.all(
        from u in Friends.Social.User,
          order_by: [desc: u.inserted_at],
          limit: 100,
          select: %{
            id: u.id,
            username: u.username,
            display_name: u.display_name,
            avatar_url: u.avatar_url,
            avatar_url_thumb: u.avatar_url_thumb
          }
      )

    user_ids = Enum.map(users, & &1.id)

    # Get edges between these users
    edges =
      Repo.all(
        from f in Friends.Social.Friendship,
          where: f.user_id in ^user_ids and f.friend_user_id in ^user_ids and f.status == "accepted",
          select: %{from: f.user_id, to: f.friend_user_id}
      )
      |> Enum.map(fn %{from: from, to: to} ->
        # Ensure consistent direction for uniqueness
        if from < to, do: %{from: from, to: to}, else: %{from: to, to: from}
      end)
      |> Enum.uniq()

    nodes =
      Enum.map(users, fn u ->
        # Use thumbnail for graph display, fall back to original
        avatar = u.avatar_url_thumb || u.avatar_url
        %{
          id: u.id,
          username: u.username,
          display_name: u.display_name || u.username,
          color: user_color(u),
          avatar_url: avatar
        }
      end)

    %{
      nodes: nodes,
      edges: edges
    }
  end
  @doc """
  Builds chord diagram data for a user's personal network.
  Returns nodes (user + connections) and a connection matrix for D3 chord layout.
  """
  def build_chord_data(nil), do: nil
  def build_chord_data(user) do
    user_id = user.id

    # Get all connections
    my_trusted = Social.list_trusted_friends(user_id)
    people_who_trust_me =
      Repo.all(
        from tf in Friends.Social.TrustedFriend,
          where: tf.trusted_user_id == ^user_id and tf.status == "confirmed",
          preload: [:user]
      )
    friends = Social.list_friends(user_id)

    # Build node list: self first, then grouped by type
    # Self node
    self_node = %{
      id: user.id,
      name: user.display_name || user.username,
      username: user.username,
      group: "self",
      color: "#ffffff"
    }
    nodes = [self_node]

    # Trusted nodes (now called Recovery)
    trusted_nodes = Enum.map(my_trusted, fn tf ->
      %{
        id: tf.trusted_user.id,
        name: tf.trusted_user.display_name || tf.trusted_user.username,
        username: tf.trusted_user.username,
        group: "recovery",
        color: "#34d399"
      }
    end)

    # People who trust me (exclude those already in trusted to avoid dupes)
    trusted_ids = MapSet.new(Enum.map(my_trusted, fn tf -> tf.trusted_user.id end))
    trusts_me_nodes = 
      people_who_trust_me
      |> Enum.reject(fn tf -> MapSet.member?(trusted_ids, tf.user.id) end)
      |> Enum.map(fn tf ->
        %{
          id: tf.user.id,
          name: tf.user.display_name || tf.user.username,
          username: tf.user.username,
          group: "recovers_me",
          color: "#a78bfa"
        }
      end)

    # Friend nodes (exclude those already in trusted/trusts_me)
    existing_ids = MapSet.union(trusted_ids, MapSet.new(Enum.map(people_who_trust_me, fn tf -> tf.user.id end)))
    friend_nodes =
      friends
      |> Enum.reject(fn f -> MapSet.member?(existing_ids, f.user.id) end)
      |> Enum.map(fn f ->
        %{
          id: f.user.id,
          name: f.user.display_name || f.user.username,
          username: f.user.username,
          group: "friend",
          color: "#3b82f6"
        }
      end)

    # Combine all nodes with indices
    all_nodes = nodes ++ trusted_nodes ++ trusts_me_nodes ++ friend_nodes
    all_nodes = all_nodes |> Enum.with_index() |> Enum.map(fn {node, idx} -> Map.put(node, :index, idx) end)
    
    # Build ID to index map
    id_to_index = Map.new(all_nodes, fn n -> {n.id, n.index} end)
    n = length(all_nodes)

    # Initialize empty matrix
    matrix = for _ <- 1..n, do: for(_ <- 1..n, do: 0)

    # Fill matrix with connections
    # Self connections to all direct connections
    self_idx = 0
    matrix = 
      all_nodes
      |> Enum.reduce(matrix, fn node, mat ->
        if node.id != user_id do
          # Connection from self to this node
          mat = put_matrix(mat, self_idx, node.index, 1)
          put_matrix(mat, node.index, self_idx, 1)
        else
          mat
        end
      end)

    # Get friendships between connections
    connection_ids = Enum.map(all_nodes, fn n -> n.id end) |> Enum.filter(fn id -> id != user_id end)
    inter_friendships = get_friendships_between(connection_ids)

    # Add inter-connection edges
    matrix =
      Enum.reduce(inter_friendships, matrix, fn {id1, id2}, mat ->
        idx1 = Map.get(id_to_index, id1)
        idx2 = Map.get(id_to_index, id2)
        if idx1 && idx2 do
          mat = put_matrix(mat, idx1, idx2, 1)
          put_matrix(mat, idx2, idx1, 1)
        else
          mat
        end
      end)

    %{
      nodes: all_nodes,
      matrix: matrix,
      groups: ["self", "recovery", "recovers_me", "friend"]
    }
  end

  @doc """
  Builds chord diagram data for a specific room.
  Shows all room members and their inter-connections.
  """
  def build_room_chord_data(nil, _room_id), do: nil
  def build_room_chord_data(_user, nil), do: nil
  def build_room_chord_data(user, room_id) do
    # Get all room members
    members = Social.list_room_members(room_id)
    
    if Enum.empty?(members) do
      nil
    else
      user_id = user.id
      
      # Build nodes from members
      all_nodes = 
        members
        |> Enum.with_index()
        |> Enum.map(fn {member, idx} ->
          is_self = member.user.id == user_id
          %{
            id: member.user.id,
            name: member.user.display_name || member.user.username,
            username: member.user.username,
            group: if(is_self, do: "self", else: "member"),
            role: member.role,
            color: if(is_self, do: "#ffffff", else: "#14b8a6"),
            index: idx
          }
        end)

      # Build ID to index map
      id_to_index = Map.new(all_nodes, fn n -> {n.id, n.index} end)
      n = length(all_nodes)

      # Initialize empty matrix
      matrix = for _ <- 1..n, do: for(_ <- 1..n, do: 0)

      # Get all friendships between room members
      member_ids = Enum.map(all_nodes, fn n -> n.id end)
      inter_friendships = get_friendships_between(member_ids)

      # Fill matrix with connections
      matrix =
        Enum.reduce(inter_friendships, matrix, fn {id1, id2}, mat ->
          idx1 = Map.get(id_to_index, id1)
          idx2 = Map.get(id_to_index, id2)
          if idx1 && idx2 do
            mat = put_matrix(mat, idx1, idx2, 1)
            put_matrix(mat, idx2, idx1, 1)
          else
            mat
          end
        end)

      %{
        nodes: all_nodes,
        matrix: matrix,
        groups: ["self", "member"],
        room_id: room_id
      }
    end
  end

  # Helper to update matrix value at [row][col]
  defp put_matrix(matrix, row, col, value) do
    List.update_at(matrix, row, fn row_list ->
      List.update_at(row_list, col, fn _ -> value end)
    end)
  end

  # Get all friendships between a list of user IDs
  # Returns a list of {user_id1, user_id2} tuples
  defp get_friendships_between([]), do: []
  defp get_friendships_between([_]), do: []
  defp get_friendships_between(user_ids) do
    alias Friends.Social.Friendship
    import Ecto.Query

    Repo.all(
      from f in Friendship,
        where: f.status == "accepted" and
               f.user_id in ^user_ids and
               f.friend_user_id in ^user_ids,
        select: {f.user_id, f.friend_user_id}
    )
  end
end
