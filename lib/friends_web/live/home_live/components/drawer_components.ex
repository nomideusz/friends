defmodule FriendsWeb.HomeLive.Components.DrawerComponents do
  @moduledoc """
  Unified bottom drawer system for mobile UI.
  All drawers slide up from the bottom and can be stacked.
  """
  use FriendsWeb, :html

  @doc """
  A reusable bottom drawer component.

  ## Attributes
    - `id` - Unique identifier for the drawer
    - `show` - Boolean to control visibility
    - `z_index` - CSS z-index for stacking (default: 50)
    - `height` - Tailwind height class (default: "h-[70vh]")
    - `close_event` - Event name to fire when closing
    - `title` - Optional header title
    - `show_backdrop` - Whether to show backdrop (default: true)
    - `inner_block` - Content slot
  """
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :z_index, :integer, default: 50
  attr :height, :string, default: "h-[70vh]"
  attr :close_event, :string, required: true
  attr :title, :string, default: nil
  attr :show_backdrop, :boolean, default: true

  slot :inner_block, required: true
  slot :header_actions

  def bottom_drawer(assigns) do
    ~H"""
    <%= if @show do %>
      <%!-- Backdrop --%>
      <%= if @show_backdrop do %>
        <div
          class="fixed inset-0 bg-black/60 backdrop-blur-sm animate-in fade-in duration-200"
          style={"z-index: #{@z_index - 1}"}
          phx-click={@close_event}
        ></div>
      <% end %>

      <%!-- Responsive Surface Wrapper --%>
      <div class="surface-overlay" style={"z-index: #{@z_index}"}>
        <%!-- Drawer Island --%>
        <div
          id={@id}
          phx-hook="SwipeableDrawer"
          data-close-event={@close_event}
          class={"surface-island aether-card #{@height} shadow-[0_-10px_40px_rgba(0,0,0,0.8)] flex flex-col"}
        >
        <%!-- Drag Handle --%>
        <div
          class="w-full pt-4 pb-2 flex flex-col items-center cursor-grab active:cursor-grabbing shrink-0 touch-none"
          phx-click={@close_event}
        >
          <div class="w-12 h-1.5 bg-white/20 rounded-full"></div>
        </div>

        <%!-- Header (if title provided) --%>
        <%= if @title do %>
          <div class="px-4 pb-3 flex items-center justify-between shrink-0 border-b border-white/5">
            <h2 class="text-sm font-bold text-white uppercase tracking-wider">{@title}</h2>
            <div class="flex items-center gap-2">
              {render_slot(@header_actions)}
            </div>
          </div>
        <% end %>

        <%!-- Content --%>
        <div class="flex-1 overflow-y-auto overflow-x-hidden">
          {render_slot(@inner_block)}
        </div>
        </div>
      </div>
    <% end %>
    """
  end

  @doc """
  Navigation drawer content - shows Contacts and Groups.
  """
  attr :users, :list, default: []
  attr :rooms, :list, default: []
  attr :new_room_name, :string, default: ""
  attr :show_graph_drawer, :boolean, default: false

  def navigation_drawer_content(assigns) do
    ~H"""
    <div class="p-4 space-y-6">
      <%!-- Contacts Section --%>
      <div>
        <div class="flex items-center justify-between mb-3 px-1">
          <h3 class="text-xs font-bold text-white/40 uppercase tracking-wider">
            Contacts ({length(@users)})
          </h3>
          <.link
            navigate="/network"
            class="text-xs text-white/50 hover:text-white transition-colors"
          >
            View All →
          </.link>
        </div>
        <%= if @users == [] do %>
          <div class="text-center py-4">
            <p class="text-xs text-white/30 italic mb-2">No contacts yet</p>
            <.link
              navigate="/network"
              class="px-3 py-1.5 rounded-lg bg-white/5 hover:bg-white/10 text-xs text-white/70 font-medium transition-colors inline-block border border-white/10"
            >
              + Add Contacts
            </.link>
          </div>
        <% else %>
          <div class="space-y-2">
            <%= for friend <- Enum.take(@users, 8) do %>
              <button
                type="button"
                phx-click="open_dm"
                phx-value-user_id={friend.user.id}
                class="w-full flex items-center gap-3 p-2 rounded-lg hover:bg-white/5 transition-colors"
              >
                <div
                  class="w-8 h-8 rounded-full flex items-center justify-center text-xs font-bold text-white"
                  style={"background-color: #{friend_color(friend.user)}"}
                >
                  {String.first(friend.user.username)}
                </div>
                <span class="text-sm text-white/70">{friend.user.username}</span>
              </button>
            <% end %>
          </div>
        <% end %>
      </div>

      <%!-- Groups Section --%>
      <div>
        <h3 class="text-xs font-bold text-white/40 uppercase tracking-wider mb-3 px-1">
          Groups ({length(Enum.reject(@rooms, &(&1.room_type == "dm")))})
        </h3>
        <div class="space-y-2">
          <%= for room <- Enum.reject(@rooms, &(&1.room_type == "dm")) |> Enum.take(6) do %>
            <.link
              navigate={~p"/r/#{room.code}"}
              class="flex items-center gap-3 p-2 rounded-lg hover:bg-white/5 transition-colors"
            >
              <div class="w-8 h-8 rounded-lg bg-white/5 border border-white/10 flex items-center justify-center text-xs">
                <%= if room.is_private do %>
                  🔒
                <% else %>
                  🌐
                <% end %>
              </div>
              <span class="text-sm text-white/70 truncate">{room.name || room.code}</span>
            </.link>
          <% end %>

          <%!-- Create Group Form --%>
          <form phx-submit="create_group" class="pt-3 border-t border-white/10">
            <div class="flex gap-2">
              <input
                type="text"
                name="name"
                value={@new_room_name}
                placeholder="New group name..."
                class="flex-1 bg-white/5 border border-white/10 rounded-xl px-3 py-2 text-sm text-white placeholder-white/30 focus:outline-none focus:border-white/30"
              />
              <button
                type="submit"
                class="px-4 py-2 bg-white/10 hover:bg-white/20 text-white text-xs font-bold uppercase rounded-xl transition-colors"
              >
                Create
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
    """
  end

  # Helper function for friend colors
  defp friend_color(%{id: id}) when is_integer(id) do
    colors = [
      "#FF6B6B", "#4ECDC4", "#45B7D1", "#96CEB4",
      "#FFEAA7", "#DDA0DD", "#98D8C8", "#F7DC6F",
      "#BB8FCE", "#85C1E9", "#F8B500", "#00CED1"
    ]
    Enum.at(colors, rem(id, length(colors)))
  end
  defp friend_color(_), do: "#888"
end
