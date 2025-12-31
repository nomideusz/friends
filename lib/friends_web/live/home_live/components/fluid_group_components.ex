defmodule FriendsWeb.HomeLive.Components.FluidGroupComponents do
  @moduledoc """
  Fluid design group components.
  Simple bottom sheet for viewing and managing groups.
  """
  use FriendsWeb, :html


  # ============================================================================
  # GROUPS SHEET
  # Bottom sheet for viewing all groups with inline creation
  # Animates from avatar's corner position
  # ============================================================================

  attr :show, :boolean, default: false
  attr :groups, :list, default: []
  attr :search_query, :string, default: ""
  attr :current_user, :map, required: true
  attr :is_admin, :boolean, default: false
  attr :new_room_name, :string, default: ""
  attr :show_create_form, :boolean, default: false
  attr :avatar_position, :string, default: "top-right"

  def groups_sheet(assigns) do
    # Check if current user is admin
    is_admin = Friends.Social.is_admin?(assigns.current_user)
    
    # Determine sheet position and animation based on avatar position
    {container_classes, content_classes, animation} = sheet_position_classes(assigns.avatar_position)
    
    assigns = assigns
      |> assign(:is_admin, is_admin)
      |> assign(:container_classes, container_classes)
      |> assign(:content_classes, content_classes)
      |> assign(:animation, animation)

    ~H"""
    <%= if @show do %>
      <div id="groups-sheet" class="fixed inset-0 z-[300]" phx-hook="LockScroll">
        <%!-- Backdrop --%>
        <div
          class="absolute inset-0 bg-black/70 backdrop-blur-sm animate-in fade-in duration-200"
          phx-click="close_groups_sheet"
        ></div>

        <%!-- Modal - positioned based on avatar corner --%>
        <div class={"absolute z-10 flex pointer-events-none " <> @container_classes <> " " <> @animation}>
          <div
            id="groups-sheet-content"
            class={"bg-neutral-900/95 backdrop-blur-xl border border-white/10 shadow-2xl max-h-[80vh] flex flex-col pointer-events-auto " <> @content_classes}
            phx-click-away="close_groups_sheet"
            phx-hook="SwipeableDrawer"
            data-close-event="close_groups_sheet"
          >
            <%!-- Handle --%>
            <div class="py-3 flex justify-center cursor-pointer" phx-click="close_groups_sheet">
              <div class="w-10 h-1 rounded-full bg-white/20"></div>
            </div>

            <%!-- Header --%>
            <div class="px-4 pb-3">
              <h2 class="text-lg font-bold text-white mb-3">Groups</h2>

              <%!-- Always-visible Create Form --%>
              <form phx-submit="create_group" class="mb-3">
                <div class="flex gap-2">
                  <input
                    type="text"
                    name="name"
                    value={@new_room_name}
                    placeholder="Group name..."
                    class="flex-1 bg-white/5 border border-white/10 rounded-lg px-3 py-2 text-sm text-white placeholder-white/30 focus:border-white/30 focus:outline-none"
                    autocomplete="off"
                  />
                  <button
                    type="submit"
                    class="px-4 py-2 bg-blue-500 hover:bg-blue-600 text-white text-sm font-medium rounded-lg transition-colors cursor-pointer"
                  >
                    Create
                  </button>
                </div>
              </form>

              <%!-- Search - only show when there are many groups --%>
              <% multi_member_groups_count = Enum.count(@groups, fn g -> g.room_type != "dm" end) %>
              <%= if multi_member_groups_count > 5 do %>
                <input
                  type="text"
                  name="group_search"
                  value={@search_query}
                  placeholder="Search groups..."
                  phx-keyup="group_search"
                  phx-debounce="200"
                  autocomplete="off"
                  class="w-full bg-white/5 border border-white/10 rounded-xl px-4 py-3 text-white placeholder-white/30 focus:border-white/30 focus:outline-none"
                />
              <% end %>
            </div>

            <%!-- Groups List (exclude DM rooms) --%>
            <div class="flex-1 overflow-y-auto px-4 pb-8">
              <% multi_member_groups = Enum.filter(@groups, fn g -> g.room_type != "dm" end) %>
              <%= if multi_member_groups == [] do %>
                <div class="flex flex-col items-center justify-center py-12 text-center">
                  <div class="w-12 h-12 rounded-xl bg-white/5 flex items-center justify-center mb-3">
                    <svg class="w-6 h-6 text-white/20" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z" />
                    </svg>
                  </div>
                  <p class="text-white/40 text-sm">No groups yet</p>
                  <p class="text-white/30 text-xs">Create your first group above</p>
                </div>
              <% else %>
                <div class="space-y-2">
                  <%= for group <- multi_member_groups do %>
                    <.group_row group={group} is_admin={@is_admin} />
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  # ============================================================================
  # GROUPS DRAWER CONTENT
  # Content-only component for use inside TetheredDrawer
  # ============================================================================

  attr :groups, :list, default: []
  attr :search_query, :string, default: ""
  attr :current_user, :map, required: true
  attr :new_room_name, :string, default: ""

  def groups_drawer_content(assigns) do
    is_admin = Friends.Social.is_admin?(assigns.current_user)
    assigns = assign(assigns, :is_admin, is_admin)

    ~H"""
    <div class="flex flex-col h-full">
      <%!-- Create Form --%>
      <div class="px-4 py-3 border-b border-white/10">
        <form phx-submit="create_group" class="flex gap-2">
          <input
            type="text"
            name="name"
            value={@new_room_name}
            placeholder="New group name..."
            class="flex-1 bg-white/5 border border-white/10 rounded-lg px-3 py-2 text-sm text-white placeholder-white/30 focus:border-white/30 focus:outline-none"
            autocomplete="off"
          />
          <button
            type="submit"
            class="px-4 py-2 bg-purple-500 hover:bg-purple-600 text-white text-sm font-medium rounded-lg transition-colors cursor-pointer"
          >
            Create
          </button>
        </form>
      </div>

      <%!-- Search (if many groups) --%>
      <% multi_member_groups_count = Enum.count(@groups, fn g -> g.room_type != "dm" end) %>
      <%= if multi_member_groups_count > 5 do %>
        <div class="px-4 py-2 border-b border-white/10">
          <input
            type="text"
            name="group_search"
            value={@search_query}
            placeholder="Search groups..."
            phx-keyup="group_search"
            phx-debounce="200"
            autocomplete="off"
            class="w-full bg-white/5 border border-white/10 rounded-lg px-3 py-2 text-sm text-white placeholder-white/30 focus:border-white/30 focus:outline-none"
          />
        </div>
      <% end %>

      <%!-- Groups List --%>
      <div class="flex-1 overflow-y-auto px-4 py-3">
        <% multi_member_groups = Enum.filter(@groups, fn g -> g.room_type != "dm" end) %>
        <%= if multi_member_groups == [] do %>
          <div class="flex flex-col items-center justify-center py-12 text-center">
            <div class="w-12 h-12 rounded-xl bg-white/5 flex items-center justify-center mb-3">
              <svg class="w-6 h-6 text-white/20" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z" />
              </svg>
            </div>
            <p class="text-white/40 text-sm">No groups yet</p>
            <p class="text-white/30 text-xs">Create your first group above</p>
          </div>
        <% else %>
          <div class="space-y-2">
            <%= for group <- multi_member_groups do %>
              <.group_row group={group} is_admin={@is_admin} />
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end


  # ============================================================================
  # GROUP ROW
  # ============================================================================

  attr :group, :map, required: true
  attr :is_admin, :boolean, default: false

  def group_row(assigns) do
    ~H"""
    <div class="flex items-center gap-3 p-3 rounded-xl bg-white/5 hover:bg-white/10 border border-white/5 hover:border-white/10 transition-all group">
      <%!-- Link wrapper for navigation --%>
      <.link
        navigate={~p"/r/#{@group.code}"}
        class="flex items-center gap-3 flex-1 min-w-0"
      >
        <%!-- Avatar --%>
        <div 
          class="w-10 h-10 rounded-lg flex items-center justify-center text-sm font-bold bg-neutral-800 text-white"
          style={if @group.emoji, do: "", else: "background-image: linear-gradient(135deg, #333 0%, #111 100%);"}
        >
          <%= if @group.emoji && @group.emoji != "" do %>
            <span class="text-lg">{@group.emoji}</span>
          <% else %>
            <span>{String.first(@group.name || @group.code || "?") |> String.upcase()}</span>
          <% end %>
        </div>

        <%!-- Info --%>
        <div class="flex-1 min-w-0">
          <div class="text-sm font-medium text-white group-hover:text-white transition-colors truncate">
            {@group.name}
          </div>
          <div class="text-[10px] text-white/40 truncate">
            {length(@group.members)} members
          </div>
        </div>

        <%!-- Arrow --%>
        <div class="text-white/20 group-hover:text-white/50 transition-colors">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
          </svg>
        </div>
      </.link>

      <%!-- Admin delete button --%>
      <%= if @is_admin do %>
        <button
          type="button"
          phx-click="admin_delete_room"
          phx-value-room_id={@group.id}
          data-confirm="Delete group '#{@group.name || @group.code}' and all its content?"
          class="w-8 h-8 rounded-lg bg-red-500/10 hover:bg-red-500/20 text-red-400 hover:text-red-300 flex items-center justify-center transition-colors"
          title="Delete group (admin)"
        >
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
          </svg>
        </button>
      <% end %>
    </div>
    """
  end

  # ============================================================================
  # SHEET POSITION HELPER
  # Returns {container_classes, content_classes, animation} based on avatar position
  # ============================================================================

  defp sheet_position_classes(position) do
    case position do
      "top-left" ->
        {
          "top-16 left-4",
          "w-80 max-w-[calc(100vw-2rem)] rounded-2xl",
          "animate-in fade-in zoom-in-95 slide-in-from-top-2 slide-in-from-left-2 duration-300"
        }
      "top-right" ->
        {
          "top-16 right-4",
          "w-80 max-w-[calc(100vw-2rem)] rounded-2xl",
          "animate-in fade-in zoom-in-95 slide-in-from-top-2 slide-in-from-right-2 duration-300"
        }
      "bottom-left" ->
        {
          "bottom-24 left-4",
          "w-80 max-w-[calc(100vw-2rem)] rounded-2xl",
          "animate-in fade-in zoom-in-95 slide-in-from-bottom-2 slide-in-from-left-2 duration-300"
        }
      "bottom-right" ->
        {
          "bottom-24 right-4",
          "w-80 max-w-[calc(100vw-2rem)] rounded-2xl",
          "animate-in fade-in zoom-in-95 slide-in-from-bottom-2 slide-in-from-right-2 duration-300"
        }
      _ ->
        # Default: top-right
        {
          "top-16 right-4",
          "w-80 max-w-[calc(100vw-2rem)] rounded-2xl",
          "animate-in fade-in zoom-in-95 slide-in-from-top-2 slide-in-from-right-2 duration-300"
        }
    end
  end
end
