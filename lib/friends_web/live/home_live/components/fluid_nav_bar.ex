defmodule FriendsWeb.HomeLive.Components.FluidNavBar do
  @moduledoc """
  Revolut-style floating navigation bar.
  
  Layout:
  [ Left: Avatar ] -------------------------------- [ Right: People | Groups ]
  
  - Avatar: Opens full-screen Settings Modal
  - People: Opens full-screen People Modal (Contacts)
  - Groups: Opens full-screen Groups Modal (Chats)
  """
  use FriendsWeb, :html
  import FriendsWeb.HomeLive.Helpers

  attr :notification, :map, default: nil
  attr :current_user, :map, required: true
  attr :pending_request_count, :integer, default: 0
  attr :unread_count, :integer, default: 0
  attr :online_friend_count, :integer, default: 0

  def fluid_nav_bar(assigns) do
    ~H"""
    <div 
      id="fluid-nav-bar" 
      class="fixed top-0 left-0 right-0 z-[100] px-4 py-3 pointer-events-none flex items-start justify-between"
    >
      <%!-- LEFT: Avatar (Settings) --%>
      <div class="pointer-events-auto relative z-20">
        <button
          phx-click="toggle_settings_modal"
          class="group relative"
        >
          <%!-- Avatar Container --%>
          <div class="w-10 h-10 rounded-full p-[2px] bg-gradient-to-br from-white/20 to-white/5 border border-white/10 shadow-lg backdrop-blur-md overflow-hidden relative transition-transform duration-300 group-hover:scale-105 group-active:scale-95">
             <div class="w-full h-full rounded-full overflow-hidden relative bg-neutral-900">
               <%= if @current_user.avatar_url do %>
                 <img src={@current_user.avatar_url} class="w-full h-full object-cover" />
               <% else %>
                  <div
                    class="w-full h-full flex items-center justify-center text-sm font-bold text-white mb-[1px]"
                    style={"background-color: #{friend_color(@current_user)}"}
                  >
                    {String.first(@current_user.username) |> String.upcase()}
                  </div>
               <% end %>
               
               <%!-- Shine effect --%>
               <div class="absolute inset-0 bg-gradient-to-tr from-transparent via-white/10 to-transparent opacity-0 group-hover:opacity-100 transition-opacity"></div>
             </div>
          </div>
        </button>
      </div>

      <%!-- CENTER: Notification Pill (Integrated) --%>
      <%= if @notification do %>
        <div class="pointer-events-auto absolute left-1/2 -translate-x-1/2 top-3 z-10 w-full max-w-md flex justify-center">
            <.notification_pill notification={@notification} />
        </div>
      <% end %>

      <%!-- RIGHT: Action Circles --%>
      <div class="pointer-events-auto flex items-center gap-3 relative z-20">
        
        <%!-- People Circle --%>
        <.nav_circle_button 
          icon="people" 
          label="People" 
          event="toggle_people_modal" 
          badge={@pending_request_count}
          info={@online_friend_count > 0 && "#{@online_friend_count}"}
          info_color="text-green-400"
        />

        <%!-- Groups Circle --%>
        <.nav_circle_button 
          icon="groups" 
          label="Groups" 
          event="toggle_groups_modal" 
          badge={@unread_count}
        />
        
      </div>
    </div>
    """
  end

  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :event, :string, required: true
  attr :badge, :integer, default: 0
  attr :info, :any, default: nil
  attr :info_color, :string, default: "text-white"

  defp nav_circle_button(assigns) do
    ~H"""
    <button
      phx-click={@event}
      class="group relative w-10 h-10 rounded-full bg-black/40 backdrop-blur-xl border border-white/10 shadow-lg flex items-center justify-center transition-all duration-300 hover:bg-white/10 hover:border-white/20 hover:scale-105 active:scale-95"
      aria-label={@label}
    >
      <%!-- Icon --%>
      <div class="w-5 h-5 text-white/80 group-hover:text-white transition-colors">
        <.nav_icon name={@icon} />
      </div>

      <%!-- Notification Badge (Red Dot) --%>
      <%= if @badge > 0 do %>
        <div class="absolute -top-1 -right-1 flex h-4 w-4">
          <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-red-400 opacity-75"></span>
          <span class="relative inline-flex rounded-full h-4 w-4 bg-red-500 border border-black items-center justify-center text-[9px] font-bold text-white">
            {@badge}
          </span>
        </div>
      <% end %>

      <%!-- Info Label (e.g. online count) - Positioning below looks cleaner --%>
      <%= if @info do %>
        <div class={"absolute -bottom-5 left-1/2 -translate-x-1/2 text-[10px] font-medium " <> @info_color}>
          {@info}
        </div>
      <% end %>
    </button>
    """
  end

  defp nav_icon(%{name: "people"} = assigns) do
    ~H"""
    <svg class="w-full h-full" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z" />
    </svg>
    """
  end

  defp nav_icon(%{name: "groups"} = assigns) do
    ~H"""
    <svg class="w-full h-full" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z" />
    </svg>
    """
  end

  attr :notification, :map, required: true
  
  def notification_pill(assigns) do
    ~H"""
    <div 
      class="animate-in slide-in-from-top fade-in duration-300"
      role="alert"
    >
      <button
        phx-click="view_notification"
        class="group relative flex items-center gap-3 pl-3 pr-4 py-2 bg-neutral-950/90 backdrop-blur-xl border border-white/10 rounded-full shadow-[0_0_20px_rgba(0,0,0,0.5)] hover:bg-neutral-900 transition-all cursor-pointer overflow-hidden max-w-[90vw] sm:max-w-md"
      >
        <%!-- Glow effect --%>
        <div class="absolute inset-0 bg-gradient-to-r from-blue-500/10 via-purple-500/10 to-blue-500/10 opacity-50 group-hover:opacity-100 transition-opacity"></div>
        
        <%!-- Icon / Avatar --%>
        <div class="w-8 h-8 rounded-full bg-white/10 flex items-center justify-center shrink-0 border border-white/10 relative z-10">
          <svg class="w-4 h-4 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 10h.01M12 10h.01M16 10h.01M9 16H5a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v8a2 2 0 01-2 2h-5l-5 5v-5z" />
          </svg>
        </div>
        
        <%!-- Text Content --%>
        <div class="flex flex-col items-start min-w-0 relative z-10">
          <div class="flex items-center gap-2">
            <span class="text-xs font-bold text-white">{@notification.sender_username}</span>
            <span class="text-[10px] text-white/40">in {@notification.room_name}</span>
          </div>
          <p class="text-xs text-white/80 truncate w-full text-left max-w-[200px]">
            {@notification.text}
          </p>
        </div>
        
        <%!-- Close Button --%>
        <div 
          role="button"
          phx-click="dismiss_notification"
          phx-click-stop
          class="ml-2 p-1 rounded-full hover:bg-white/10 text-white/30 hover:text-white transition-colors relative z-10"
        >
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </div>
      </button>
    </div>
    """
  end
end
