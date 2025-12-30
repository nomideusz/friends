defmodule FriendsWeb.UserSocket do
  @moduledoc """
  WebSocket for API clients (SvelteKit, mobile apps).
  Supports channels for real-time updates.
  """
  use Phoenix.Socket

  # Channels
  channel "friends:*", FriendsWeb.FriendsChannel

  @impl true
  def connect(_params, socket, _connect_info) do
    # For now, allow all connections (could add auth later)
    {:ok, socket}
  end

  @impl true
  def id(_socket), do: nil
end
