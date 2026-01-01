defmodule Friends.GraphCache do
  @moduledoc """
  Caches graph data to avoid expensive queries on every graph view.
  - User-specific graph data is cached for 10 minutes per user.
  - Global welcome graph is cached for 5 minutes (shared by all users).
  """

  @cache_name :graph_cache
  @ttl :timer.minutes(10)
  @welcome_ttl :timer.minutes(5)
  @welcome_cache_key "graph:welcome:global"

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

  # --- Welcome Graph Caching ---

  @doc """
  Fetches the global welcome graph data, using cache when available.
  This is shared by all users viewing the welcome/network graph.
  """
  def get_welcome_graph_data do
    case Cachex.get(@cache_name, @welcome_cache_key) do
      {:ok, nil} ->
        # Not in cache, build it
        graph_data = FriendsWeb.HomeLive.GraphHelper.build_welcome_graph_data()
        Cachex.put(@cache_name, @welcome_cache_key, graph_data, ttl: @welcome_ttl)
        graph_data

      {:ok, graph_data} ->
        # Cache hit
        graph_data

      {:error, _reason} ->
        # Cache error, build without caching
        FriendsWeb.HomeLive.GraphHelper.build_welcome_graph_data()
    end
  end

  @doc """
  Invalidates the global welcome graph cache.
  Call this when new users register or global friendships change.
  """
  def invalidate_welcome do
    Cachex.del(@cache_name, @welcome_cache_key)
  end
end
