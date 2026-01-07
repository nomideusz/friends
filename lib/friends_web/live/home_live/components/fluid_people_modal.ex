defmodule FriendsWeb.HomeLive.Components.FluidPeopleModal do
  @moduledoc """
  Full-screen modal for People (Contacts).
  """
  use FriendsWeb, :html
  import FriendsWeb.HomeLive.Components.FluidContactComponents

  attr :show, :boolean, default: false
  attr :contact_mode, :string, default: "list"
  attr :contacts, :list, default: []
  attr :search_query, :string, default: ""
  attr :search_results, :list, default: []
  
  # Pass-through props for drawer content (simplified for now)
  attr :trusted_friend_ids, :any, default: MapSet.new()
  attr :trusted_friends, :list, default: []
  attr :incoming_trust_requests, :list, default: []
  attr :outgoing_requests, :list, default: []
  attr :outgoing_trust_requests, :list, default: []
  attr :pending_friend_requests, :list, default: []
  attr :room, :any, default: nil
  attr :room_members, :list, default: []
  attr :current_user, :map, required: true
  attr :online_friend_ids, :any, default: MapSet.new()

  def fluid_people_modal(assigns) do
    ~H"""
    <%= if @show do %>
      <div 
        id="fluid-people-modal" 
        class="fixed inset-0 z-[200]"
        phx-window-keydown="close_people_modal"
        phx-key="escape"
      >
        <%!-- Backdrop --%>
        <div 
          class="absolute inset-0 bg-black/80 backdrop-blur-sm animate-in fade-in duration-300"
          phx-click="close_people_modal"
        ></div>

        <%!-- Modal Content --%>
        <div class="absolute inset-0 bg-neutral-950 animate-in slide-in-from-bottom duration-300 flex flex-col sm:inset-4 sm:rounded-2xl sm:overflow-hidden sm:border sm:border-white/10 sm:max-w-2xl sm:mx-auto sm:shadow-2xl">
          <%!-- Header --%>
          <div class="p-6 border-b border-white/10 flex items-center justify-between bg-black/20 shrink-0">
            <h2 class="text-2xl font-bold text-white tracking-tight">People</h2>
            <button 
              phx-click="close_people_modal"
              class="w-8 h-8 flex items-center justify-center rounded-full bg-white/10 hover:bg-white/20 text-white/70 hover:text-white transition-colors"
            >
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" /></svg>
            </button>
          </div>

          <%!-- Content --%>
          <div class="flex-1 overflow-y-auto p-4 scrollbar-hide">
            <.people_drawer_content
               mode={@contact_mode}
               contacts={@contacts}
               search_query={@search_query}
               search_results={@search_results}
               trusted_friend_ids={@trusted_friend_ids}
               trusted_friends={@trusted_friends}
               incoming_trust_requests={@incoming_trust_requests}
               outgoing_requests={@outgoing_requests}
               outgoing_trust_requests={@outgoing_trust_requests}
               pending_friend_requests={@pending_friend_requests}
               room={@room}
               room_members={@room_members}
               current_user={@current_user}
               online_friend_ids={@online_friend_ids}
            />
          </div>
        </div>
      </div>
    <% end %>
    """
  end
end
