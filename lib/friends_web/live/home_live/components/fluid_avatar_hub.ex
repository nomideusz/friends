defmodule FriendsWeb.HomeLive.Components.FluidAvatarHub do
  @moduledoc """
  Avatar Hub - The central navigation point for the "New Internet" experience.
  
  The user's avatar becomes a personal hub that provides access to:
  - Groups (private rooms)
  - People (contacts/friends)
  - Graph (network visualization)
  - Settings (profile/account)
  
  Features a radial menu that fans out above the avatar on tap.
  """
  use FriendsWeb, :html
  import FriendsWeb.HomeLive.Helpers

  # ============================================================================
  # AVATAR HUB
  # Floating avatar with radial navigation menu
  # ============================================================================

  attr :current_user, :map, required: true
  attr :show_menu, :boolean, default: false
  attr :pending_request_count, :integer, default: 0
  attr :unread_count, :integer, default: 0
  attr :online_friend_count, :integer, default: 0

  def avatar_hub(assigns) do
    # Fixed position: top-right
    assigns = assigns
      |> assign(:position_classes, "fixed top-3 right-4")
      |> assign(:menu_classes, "absolute top-14 right-0")
      |> assign(:menu_origin, "origin-top-right")
      |> assign(:menu_anim, "slide-in-from-top-4")
    
    ~H"""
    <div id="avatar-hub-container" class={"#{@position_classes} z-[100]"}>
      <%!-- Backdrop when menu is open --%>
      <%= if @show_menu do %>
        <div
          class="fixed inset-0 z-[-1] bg-black/40 backdrop-blur-[2px]"
          phx-click="close_avatar_menu"
        ></div>
      <% end %>

      <%!-- Menu --%>
      <%= if @show_menu do %>
        <div class={@menu_classes <> " z-10"}>
          <%!-- Menu container with enhanced glassmorphism --%>
          <div class={[
            "p-2 min-w-[240px] rounded-[2rem]",
            "bg-black/60 backdrop-blur-2xl saturate-150",
            "border border-white/15",
            "shadow-[0_20px_60px_-15px_rgba(0,0,0,0.8),inset_0_1px_0_rgba(255,255,255,0.1)]",
            "animate-in fade-in zoom-in-95 duration-300 ease-out",
            @menu_origin,
            @menu_anim
          ]}>
            <%!-- Navigation Section --%>
            <div class="flex flex-col gap-1">
              <%!-- Groups --%>
              <.hub_menu_item
                icon="spaces"
                label="Groups"
                event="open_groups_sheet"
                badge={@unread_count}
                delay="0"
                color="purple"
              />
              
              <%!-- People --%>
              <.hub_menu_item
                icon="people"
                label="People"
                event="open_contacts_sheet"
                badge={@pending_request_count}
                delay="50"
                color="blue"
                subtitle={"#{@online_friend_count} online"}
              />
              
              <%!-- Graph --%>
              <.hub_menu_item
                icon="graph"
                label="My Graph"
                event="show_my_constellation"
                delay="100"
                color="emerald"
              />
              
              <%!-- Settings/Profile --%>
              <.hub_menu_item
                icon="settings"
                label="Settings"
                event="open_profile_sheet"
                delay="150"
                color="neutral"
              />
            </div>
            
            <%!-- Separator --%>
            <div class="h-px bg-white/10 my-1.5 mx-2"></div>
            
            <%!-- Sign Out --%>
            <button
              type="button"
              phx-click="request_sign_out"
              data-confirm="Sign out of your account?"
              class="w-full flex items-center gap-3 px-3 py-2 rounded-xl text-red-400/70 hover:text-red-400 hover:bg-red-500/10 transition-all cursor-pointer group"
            >
              <div class="w-7 h-7 rounded-lg bg-red-500/10 flex items-center justify-center group-hover:bg-red-500/20 transition-colors">
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1" />
                </svg>
              </div>
              <span class="text-sm">Sign Out</span>
            </button>
          </div>
        </div>
      <% end %>

      <%!-- Avatar Button --%>
      <button
        id="avatar-hub-trigger"
        type="button"
        phx-click="toggle_avatar_menu"
        class={[
          "w-10 h-10 rounded-full border transition-all cursor-pointer shadow-lg",
          "bg-neutral-800 overflow-hidden",
          @show_menu && "border-white/40 ring-2 ring-white/20 scale-110",
          not @show_menu && "border-white/20 hover:border-white/40 hover:scale-105"
        ]}
        title={"@#{@current_user.username}"}
      >
        <div class="w-full h-full relative">
          <%= if @current_user.avatar_url do %>
            <img src={@current_user.avatar_url} alt="" class="w-full h-full object-cover" />
          <% else %>
            <div
              class="w-full h-full flex items-center justify-center text-sm font-bold"
              style={"background-color: #{friend_color(@current_user)}; color: white;"}
            >
              <%= String.first(@current_user.username) |> String.upcase() %>
            </div>
          <% end %>
        </div>
        
        <%!-- Combined badge indicator --%>
        <% total_badges = @pending_request_count + @unread_count %>
        <%= if total_badges > 0 do %>
          <span class="absolute -bottom-1 -right-1 min-w-[18px] h-[18px] flex items-center justify-center text-[10px] font-bold bg-red-500 text-white rounded-full px-1 border-2 border-neutral-900">
            <%= if total_badges > 99, do: "99+", else: total_badges %>
          </span>
        <% end %>
      </button>
    </div>
    """
  end

  # ============================================================================
  # POSITION PICKER
  # Corner selection UI in menu
  # ============================================================================

  attr :current, :string, default: "top-right"

  defp position_picker(assigns) do
    ~H"""
    <div class="flex items-center gap-2 px-3 py-2">
      <span class="text-[10px] text-white/40 uppercase tracking-wide">Move to:</span>
      <div class="flex gap-1">
        <.corner_button corner="top-left" current={@current} label="↖" />
        <.corner_button corner="top-right" current={@current} label="↗" />
        <.corner_button corner="bottom-left" current={@current} label="↙" />
        <.corner_button corner="bottom-right" current={@current} label="↘" />
      </div>
    </div>
    """
  end

  attr :corner, :string, required: true
  attr :current, :string, required: true
  attr :label, :string, required: true

  defp corner_button(assigns) do
    is_current = assigns.corner == assigns.current
    assigns = assign(assigns, :is_current, is_current)
    ~H"""
    <button
      type="button"
      phx-click="set_avatar_position"
      phx-value-position={@corner}
      class={[
        "w-7 h-7 rounded-md flex items-center justify-center text-sm transition-all cursor-pointer",
        @is_current && "bg-white/20 text-white",
        not @is_current && "bg-white/5 text-white/40 hover:bg-white/10 hover:text-white/70"
      ]}
      disabled={@is_current}
    >
      {@label}
    </button>
    """
  end

  # ============================================================================
  # HUB MENU ITEM
  # Individual menu option with icon, label, and optional badge
  # ============================================================================

  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :event, :string, required: true
  attr :badge, :integer, default: 0
  attr :delay, :string, default: "0"
  attr :color, :string, default: "neutral"
  attr :subtitle, :string, default: nil

  defp hub_menu_item(assigns) do
    # Color mappings for icon backgrounds and hover states
    {icon_bg, hover_bg, icon_text} = case assigns.color do
      "purple" -> {"bg-purple-500/10", "hover:bg-purple-500/10", "text-purple-400"}
      "blue" -> {"bg-blue-500/10", "hover:bg-blue-500/10", "text-blue-400"}
      "emerald" -> {"bg-emerald-500/10", "hover:bg-emerald-500/10", "text-emerald-400"}
      _ -> {"bg-white/5", "hover:bg-white/10", "text-white/70"}
    end
    
    assigns = assigns
      |> assign(:icon_bg, icon_bg)
      |> assign(:hover_bg, hover_bg)
      |> assign(:icon_text, icon_text)
    
    ~H"""
    <button
      type="button"
      phx-click={@event}
      class={[
        "w-full flex items-center gap-3 px-3.5 py-2.5 rounded-2xl transition-all cursor-pointer group",
        @hover_bg
      ]}
      style={"animation-delay: #{@delay}ms;"}
    >
      <div class={"w-8 h-8 rounded-xl flex items-center justify-center transition-transform group-hover:scale-110 " <> @icon_bg <> " " <> @icon_text}>
        <.hub_icon name={@icon} />
      </div>
      
      <div class="flex-1 text-left">
        <div class="text-[15px] font-medium text-white/90 group-hover:text-white transition-colors">{@label}</div>
        <%= if @subtitle do %>
          <div class="text-[10px] text-white/40 font-medium">{@subtitle}</div>
        <% end %>
      </div>
      
      <%= if @badge > 0 do %>
        <span class="min-w-[20px] h-[20px] flex items-center justify-center text-[10px] font-bold bg-white text-black rounded-full px-1 shadow-lg group-hover:scale-110 transition-transform">
          <%= if @badge > 99, do: "99+", else: @badge %>
        </span>
      <% end %>
    </button>
    """
  end

  # ============================================================================
  # HUB ICONS
  # SVG icons for menu items
  # ============================================================================

  defp hub_icon(%{name: "spaces"} = assigns) do
    ~H"""
    <svg class="w-5 h-5 text-purple-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2V6zM14 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2V6zM4 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2v-2zM14 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2v-2z" />
    </svg>
    """
  end

  defp hub_icon(%{name: "people"} = assigns) do
    ~H"""
    <svg class="w-5 h-5 text-blue-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z" />
    </svg>
    """
  end

  defp hub_icon(%{name: "graph"} = assigns) do
    ~H"""
    <svg class="w-5 h-5 text-emerald-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <%!-- Constellation/network graph icon - 3 connected nodes --%>
      <circle cx="12" cy="5" r="2" stroke-width="1.5" />
      <circle cx="6" cy="17" r="2" stroke-width="1.5" />
      <circle cx="18" cy="17" r="2" stroke-width="1.5" />
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M12 7v5M8.5 15.5L11 12M15.5 15.5L13 12" />
    </svg>
    """
  end

  defp hub_icon(%{name: "settings"} = assigns) do
    ~H"""
    <svg class="w-5 h-5 text-white/70" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
    </svg>
    """
  end

  defp hub_icon(assigns) do
    ~H"""
    <svg class="w-5 h-5 text-white/60" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16M4 18h16" />
    </svg>
    """
  end
end
