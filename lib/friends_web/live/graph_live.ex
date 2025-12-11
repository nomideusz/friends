defmodule FriendsWeb.GraphLive do
  use FriendsWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, push_navigate(socket, to: ~p"/network?view=graph")}
  end

  @impl true
  def render(assigns) do
    ~H""
  end
end
