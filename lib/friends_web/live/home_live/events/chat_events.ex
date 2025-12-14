defmodule FriendsWeb.HomeLive.Events.ChatEvents do
  @moduledoc """
  Event handlers for Chat UI interactions.
  """
  import Phoenix.Component
  # import Phoenix.LiveView

  def toggle_mobile_chat(socket) do
    {:noreply, update(socket, :show_mobile_chat, &(!&1))}
  end
end
