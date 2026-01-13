defmodule FriendsWeb.HomeLive.Components.FluidGraphModal do
  @moduledoc """
  Full-screen modal for the Network Graph visualization.
  """
  use FriendsWeb, :html

  attr :show, :boolean, default: false
  attr :graph_data, :any, default: nil

  def fluid_graph_modal(assigns) do
    ~H"""
    <%= if @show do %>
      <div 
        id="fluid-graph-modal" 
        class="fixed inset-0 z-[200]"
        phx-window-keydown="toggle_graph_drawer"
        phx-key="escape"
      >
        <%!-- Backdrop --%>
        <div 
          class="absolute inset-0 bg-black/80 backdrop-blur-sm animate-in fade-in duration-300"
          phx-click="toggle_graph_drawer"
        ></div>

        <%!-- Modal Content --%>
        <div class="absolute inset-0 bg-neutral-950 animate-in slide-in-from-bottom duration-300 flex flex-col sm:inset-4 sm:rounded-2xl sm:overflow-hidden sm:border sm:border-white/10 sm:max-w-2xl sm:mx-auto sm:shadow-2xl">
          <%!-- Header --%>
          <div class="p-6 border-b border-white/10 flex items-center justify-between bg-black/20 shrink-0">
            <h2 class="text-2xl font-bold text-white tracking-tight">Your Network</h2>
            <div class="flex items-center gap-2">
              <button
                phx-click="open_contacts_sheet"
                class="bg-blue-600/30 text-blue-200 px-4 py-2 rounded-full text-xs font-bold uppercase tracking-widest hover:bg-blue-600/50 transition-colors cursor-pointer"
              >
                Set up Network
              </button>
              <button 
                phx-click="toggle_graph_drawer"
                class="w-8 h-8 flex items-center justify-center rounded-full bg-white/10 hover:bg-white/20 text-white/70 hover:text-white transition-colors cursor-pointer"
              >
                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" /></svg>
              </button>
            </div>
          </div>

          <%!-- Content --%>
          <div class="flex-1 overflow-hidden p-4">
            <%= if @graph_data do %>
              <div
                id="modal-network-graph"
                phx-hook="FriendGraph"
                phx-update="ignore"
                data-graph={Jason.encode!(@graph_data)}
                class="w-full h-full min-h-[400px]"
              >
              </div>
            <% else %>
              <div class="flex items-center justify-center h-full text-neutral-500">
                <div class="text-center">
                  <svg class="w-12 h-12 mx-auto mb-3 opacity-50" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1" />
                  </svg>
                  <p class="text-sm">Add people to see your constellation</p>
                  <button phx-click="open_contacts_sheet" class="text-xs text-blue-400 hover:underline mt-2 inline-block cursor-pointer">
                    Go to Network →
                  </button>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    <% end %>
    """
  end
end
