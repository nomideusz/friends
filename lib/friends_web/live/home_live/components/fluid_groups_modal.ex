defmodule FriendsWeb.HomeLive.Components.FluidGroupsModal do
  @moduledoc """
  Full-screen modal for Groups.
  """
  use FriendsWeb, :html
  import FriendsWeb.HomeLive.Components.FluidGroupComponents

  attr :show, :boolean, default: false
  attr :groups, :list, default: []
  attr :search_query, :string, default: ""
  attr :current_user, :map, required: true
  attr :new_room_name, :string, default: ""

  def fluid_groups_modal(assigns) do
    ~H"""
    <%= if @show do %>
      <div 
        id="fluid-groups-modal" 
        class="fixed inset-0 z-[200]"
        phx-window-keydown="close_groups_modal"
        phx-key="escape"
      >
        <%!-- Backdrop --%>
        <div 
          class="absolute inset-0 bg-black/80 backdrop-blur-sm animate-in fade-in duration-300"
          phx-click="close_groups_modal"
        ></div>

        <%!-- Modal Content --%>
        <div class="absolute inset-0 bg-neutral-950 animate-in slide-in-from-bottom duration-300 flex flex-col sm:inset-4 sm:rounded-2xl sm:overflow-hidden sm:border sm:border-white/10 sm:max-w-2xl md:max-w-4xl lg:max-w-5xl sm:mx-auto sm:shadow-2xl">
          <%!-- Header --%>
          <div class="p-6 border-b border-white/10 flex items-center justify-between bg-black/20 shrink-0">
            <h2 class="text-2xl font-bold text-white tracking-tight">Groups</h2>
            <button 
              phx-click="close_groups_modal"
              class="w-8 h-8 flex items-center justify-center rounded-full bg-white/10 hover:bg-white/20 text-white/70 hover:text-white transition-colors"
            >
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" /></svg>
            </button>
          </div>

          <%!-- Content --%>
          <div class="flex-1 overflow-y-auto p-4 scrollbar-hide">
            <.groups_drawer_content
              groups={@groups}
              search_query={@search_query}
              current_user={@current_user}
              new_room_name={@new_room_name}
            />
          </div>
        </div>
      </div>
    <% end %>
    """
  end
end
