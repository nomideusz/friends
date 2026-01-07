defmodule FriendsWeb.HomeLive.Components.FluidSettingsModal do
  @moduledoc """
  Full-screen modal for Settings.
  """
  use FriendsWeb, :html
  import FriendsWeb.HomeLive.Components.FluidProfileComponents

  attr :show, :boolean, default: false
  attr :current_user, :map, required: true
  attr :devices, :list, default: []
  attr :uploads, :map, default: nil

  def fluid_settings_modal(assigns) do
    ~H"""
    <%= if @show do %>
      <div 
        id="fluid-settings-modal" 
        class="fixed inset-0 z-[200]"
        phx-window-keydown="close_settings_modal"
        phx-key="escape"
      >
        <%!-- Backdrop --%>
        <div 
          class="absolute inset-0 bg-black/80 backdrop-blur-sm animate-in fade-in duration-300"
          phx-click="close_settings_modal"
        ></div>

        <%!-- Modal Content --%>
        <div class="absolute inset-0 bg-neutral-950 animate-in slide-in-from-bottom duration-300 flex flex-col sm:inset-4 sm:rounded-2xl sm:overflow-hidden sm:border sm:border-white/10 sm:max-w-2xl sm:mx-auto sm:shadow-2xl">
          <%!-- Header --%>
          <div class="p-6 border-b border-white/10 flex items-center justify-between bg-black/20 shrink-0">
            <h2 class="text-2xl font-bold text-white tracking-tight">Settings</h2>
            <button 
              phx-click="close_settings_modal"
              class="w-8 h-8 flex items-center justify-center rounded-full bg-white/10 hover:bg-white/20 text-white/70 hover:text-white transition-colors"
            >
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" /></svg>
            </button>
          </div>

          <%!-- Content --%>
          <div class="flex-1 overflow-y-auto p-6 scrollbar-hide">
            <div class="max-w-xl mx-auto space-y-8">
              <.settings_drawer_content 
                current_user={@current_user}
                devices={@devices}
                uploads={@uploads}
                is_modal={true}
              />
            </div>
          </div>
        </div>
      </div>
    <% end %>
    """
  end
end
