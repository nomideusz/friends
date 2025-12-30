defmodule FriendsWeb.Live.Hooks.UserAuth do
  @moduledoc """
  LiveView on_mount hook for user authentication and shared assigns.

  This hook loads the current user from the session and sets up common assigns
  needed by the header and other shared components across all pages.
  """
  import Phoenix.Component, only: [assign_new: 3]
  alias Friends.Social

  # User color palette - must match HomeLive
  @colors ~w(#ef4444 #f97316 #eab308 #22c55e #14b8a6 #3b82f6 #8b5cf6 #ec4899)

  @doc """
  Called on mount for all LiveViews in the :authenticated live_session.
  Sets up user-related assigns needed for the shared header.
  """
  def on_mount(:default, _params, session, socket) do
    socket = assign_user_data(socket, session)
    {:cont, socket}
  end

  def on_mount(:optional, _params, session, socket) do
    # Same as default but doesn't require authentication
    socket = assign_user_data(socket, session)
    {:cont, socket}
  end

  defp assign_user_data(socket, session) do
    socket
    |> assign_new(:current_user, fn -> load_user(session) end)
    |> assign_derived_user_data()
    |> assign_header_data()
  end

  defp load_user(session) do
    case session["user_id"] do
      nil -> nil
      user_id -> Social.get_user(user_id)
    end
  end

  defp assign_derived_user_data(socket) do
    user = socket.assigns[:current_user]

    socket
    |> assign_new(:user_color, fn -> user_color(user) end)
    |> assign_new(:user_name, fn -> user && (user.display_name || user.username) end)
    |> assign_new(:auth_status, fn -> if user, do: :authed, else: :anon end)
  end

  defp assign_header_data(socket) do
    user = socket.assigns[:current_user]

    socket
    |> assign_new(:pending_requests, fn ->
      if user, do: Social.list_friend_requests(user.id), else: []
    end)
    # TODO: implement if needed
    |> assign_new(:recovery_requests, fn -> [] end)
    |> assign_new(:current_session_token, fn -> nil end)
    |> assign_new(:user_private_rooms, fn ->
      if user, do: Social.list_user_rooms(user.id), else: []
    end)
    |> assign_new(:public_rooms, fn -> Social.list_public_rooms() end)
    |> assign_new(:show_header_dropdown, fn -> false end)
    |> assign_new(:show_user_dropdown, fn -> false end)
  end

  defp user_color(nil), do: "#888"

  defp user_color(%{id: id}) when is_integer(id) do
    Enum.at(@colors, rem(id, length(@colors)))
  end

  defp user_color(_), do: "#888"
end
