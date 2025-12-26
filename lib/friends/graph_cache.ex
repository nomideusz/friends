defmodule Friends.GraphCache do
  @moduledoc """
  Caches graph data to avoid expensive queries on every graph view.
  Graph data is cached for 10 minutes per user.
  """

  @cache_name :graph_cache
  @ttl :timer.minutes(10)

  @doc """
  Fetches graph data for a user, using cache when available.
  Falls back to building the graph if not cached.
  """
  def get_graph_data(user) do
    cache_key = "graph:user:#{user.id}"

    case Cachex.get(@cache_name, cache_key) do
      {:ok, nil} ->
        # Not in cache, build it
        graph_data = FriendsWeb.HomeLive.GraphHelper.build_graph_data(user)
        Cachex.put(@cache_name, cache_key, graph_data, ttl: @ttl)
        graph_data

      {:ok, graph_data} ->
        # Cache hit
        graph_data

      {:error, _reason} ->
        # Cache error, build without caching
        FriendsWeb.HomeLive.GraphHelper.build_graph_data(user)
    end
  end

  @doc """
  Invalidates the graph cache for a specific user.
  Call this when friendships/trust relationships change.
  """
  def invalidate(user_id) do
    cache_key = "graph:user:#{user_id}"
    Cachex.del(@cache_name, cache_key)
  end

  @doc """
  Invalidates graph cache for multiple users.
  Useful when a friendship affects both users' graphs.
  """
  def invalidate_many(user_ids) when is_list(user_ids) do
    Enum.each(user_ids, &invalidate/1)
  end

  @doc """
  Clears all graph cache entries.
  """
  def clear_all do
    Cachex.clear(@cache_name)
  end
end
