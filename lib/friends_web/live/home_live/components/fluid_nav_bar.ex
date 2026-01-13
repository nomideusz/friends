defmodule FriendsWeb.HomeLive.Components.FluidNavBar do
  @moduledoc """
  Revolut-style floating navigation bar with unified notification tray.

  Layout:
  [ Left: Avatar ] -------------------------------- [ Right: People | Groups ]

  - Avatar: Opens full-screen Settings Modal
  - People: Opens full-screen People Modal (Contacts)
  - Groups: Opens full-screen Groups Modal (Chats)
  - Center: Expandable notification tray (replaces single notification pill)
  """
  use FriendsWeb, :html
  import FriendsWeb.HomeLive.Helpers

  # Legacy single notification (for backward compatibility during migration)
  attr :notification, :map, default: nil
  # New unified notifications list
  attr :notifications, :list, default: []
  attr :notifications_expanded, :boolean, default: false
  attr :notifications_unread_count, :integer, default: 0
  attr :current_user, :map, required: true
  attr :pending_request_count, :integer, default: 0
  attr :unread_count, :integer, default: 0
  attr :online_friend_count, :integer, default: 0
  attr :friends, :list, default: []
  attr :online_friend_ids, :any, default: MapSet.new()

  def fluid_nav_bar(assigns) do
    ~H"""
    <div 
      id="fluid-nav-bar" 
      class="fixed top-0 left-0 right-0 z-[100] px-4 py-3 pointer-events-none flex items-start justify-between"
    >
      <%!-- LEFT: Avatar (Settings) --%>
      <div class="pointer-events-auto relative z-20">
        <button
          phx-click="open_profile_sheet"
          class="group relative cursor-pointer"
        >
          <%!-- Avatar Container --%>
          <div class="w-10 h-10 rounded-full p-[2px] bg-gradient-to-br from-white/20 to-white/5 border border-white/10 shadow-lg backdrop-blur-md overflow-hidden relative transition-transform duration-300 group-hover:scale-105 group-active:scale-95">
             <div class="w-full h-full rounded-full overflow-hidden relative bg-neutral-900">
               <%= if @current_user.avatar_url do %>
                 <img src={@current_user.avatar_url_thumb || @current_user.avatar_url} class="w-full h-full object-cover" />
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

      <%!-- CENTER: Notification Tray (Unified) --%>
      <div class="pointer-events-auto absolute z-10 top-3 flex justify-center left-[3.75rem] right-[7.5rem] sm:left-1/2 sm:right-auto sm:-translate-x-1/2 sm:w-full sm:max-w-md">
        <%= if @notifications_expanded do %>
          <.notification_tray_expanded notifications={@notifications} />
        <% else %>
          <.notification_pill_collapsed
            notifications={@notifications}
            unread_count={@notifications_unread_count}
          />
        <% end %>
      </div>

      <%!-- RIGHT: Action Circles --%>
      <div class="pointer-events-auto flex items-center gap-3 relative z-20">
        
        <%!-- People Circle --%>
        <div id="people-icon-container" phx-hook="PeopleLongPress" class="relative">
          <.nav_circle_button
            icon="people"
            label="People"
            event="toggle_people_modal"
            has_activity={@pending_request_count > 0}
            glow_color="blue"
            info={@online_friend_count > 0 && "#{@online_friend_count}"}
            info_color="text-green-400"
          />

          <%!-- Suggested Contacts Dropdown (hidden by default) --%>
          <div id="suggested-contacts-dropdown" class="hidden absolute top-full right-0 mt-2 w-64 bg-neutral-900/95 backdrop-blur-xl border border-white/10 rounded-xl shadow-2xl overflow-hidden animate-in slide-in-from-top-2 fade-in duration-200">
            <div class="p-3 border-b border-white/10">
              <div class="flex items-center gap-2">
                <svg class="w-4 h-4 text-blue-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z" />
                </svg>
                <span class="text-xs font-medium text-white/80">Quick Contacts</span>
              </div>
            </div>
            <div class="p-2 space-y-1 max-h-80 overflow-y-auto scrollbar-hide">
              <%= if @friends && Enum.any?(@friends) do %>
                <%= for {friend, index} <- Enum.with_index(Enum.take(@friends, 5)) do %>
                  <% user = if Map.has_key?(friend, :user), do: friend.user, else: friend %>
                  <% is_online = @online_friend_ids && MapSet.member?(@online_friend_ids, user.id) %>
                  <button
                    phx-click="open_dm_with_friend"
                    phx-value-user-id={user.id}
                    class="w-full flex items-center gap-3 p-2 rounded-lg hover:bg-white/5 transition-colors cursor-pointer group"
                  >
                    <%!-- Avatar --%>
                    <div class="relative">
                      <div class="w-8 h-8 rounded-full flex items-center justify-center text-white text-xs font-medium"
                           style={"background-color: #{user.user_color};"}>
                        {String.slice(user.username, 0, 2) |> String.upcase()}
                      </div>
                      <%= if is_online do %>
                        <div class="absolute -bottom-0.5 -right-0.5 w-3 h-3 bg-green-500 rounded-full border-2 border-neutral-900"></div>
                      <% end %>
                    </div>

                    <%!-- Name --%>
                    <div class="flex-1 text-left">
                      <div class="text-sm text-white/90 group-hover:text-white">{user.username}</div>
                      <%= if index == 0 do %>
                        <div class="text-[10px] text-blue-400">Most contacted</div>
                      <% end %>
                    </div>

                    <%!-- Arrow --%>
                    <svg class="w-4 h-4 text-white/30 group-hover:text-white/60" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
                    </svg>
                  </button>
                <% end %>
              <% else %>
                <div class="text-center py-4 text-white/30 text-xs">
                  No contacts yet
                </div>
              <% end %>
            </div>
          </div>
        </div>

        <%!-- Groups Circle --%>
        <.nav_circle_button
          icon="groups"
          label="Groups"
          event="toggle_groups_modal"
          has_activity={@unread_count > 0}
          glow_color="purple"
        />
        
      </div>
    </div>
    """
  end

  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :event, :string, required: true
  attr :has_activity, :boolean, default: false
  attr :glow_color, :string, default: "blue"
  attr :info, :any, default: nil
  attr :info_color, :string, default: "text-white"

  defp nav_circle_button(assigns) do
    glow_class = case assigns.glow_color do
      "blue" -> "nav-activity-glow-blue"
      "purple" -> "nav-activity-glow-purple"
      "green" -> "nav-activity-glow-green"
      _ -> "nav-activity-glow-blue"
    end
    assigns = assign(assigns, :glow_class, glow_class)

    ~H"""
    <button
      phx-click={@event}
      class={"group relative w-10 h-10 rounded-full bg-black/40 backdrop-blur-xl border border-white/10 shadow-lg flex items-center justify-center transition-all duration-300 hover:bg-white/10 hover:border-white/20 hover:scale-105 active:scale-95 cursor-pointer " <> if(@has_activity, do: @glow_class, else: "")}
      aria-label={@label}
    >
      <%!-- Icon --%>
      <div class="w-5 h-5 text-white/80 group-hover:text-white transition-colors">
        <.nav_icon name={@icon} />
      </div>

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

  # --- Unified Notification Tray Components ---

  attr :notifications, :list, required: true
  attr :unread_count, :integer, default: 0

  defp notification_pill_collapsed(assigns) do
    ~H"""
    <button
      phx-click="toggle_notifications_tray"
      class={"group relative flex items-center gap-2 px-3 h-10 bg-neutral-950/90 backdrop-blur-xl border border-white/10 rounded-full shadow-lg hover:bg-neutral-900 transition-all cursor-pointer " <> if(@unread_count > 0, do: "notification-pulse-glow", else: "")}
    >
      <%!-- Bell Icon --%>
      <div class="w-5 h-5 flex items-center justify-center relative z-10">
        <svg class="w-4 h-4 text-white/70" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9" />
        </svg>
      </div>

      <%!-- Latest notification preview --%>
      <%= if length(@notifications) > 0 do %>
        <% latest = List.first(@notifications) %>
        <span class="text-xs text-white/80 truncate max-w-[120px] sm:max-w-[180px] relative z-10">
          <span class="font-medium">@{latest.actor_username}</span>
          <span class="text-white/50 ml-1">{latest.text}</span>
        </span>
      <% else %>
        <span class="text-xs text-white/40 relative z-10">No notifications</span>
      <% end %>

      <%!-- Unread indicator dot --%>
      <%= if @unread_count > 0 do %>
        <div class="w-2 h-2 rounded-full bg-blue-400 notification-dot-pulse relative z-10"></div>
      <% end %>
    </button>
    """
  end

  attr :notifications, :list, required: true

  defp notification_tray_expanded(assigns) do
    ~H"""
    <div class="w-full max-w-md animate-in slide-in-from-top duration-200">
      <div class="bg-neutral-950/95 backdrop-blur-xl border border-white/10 rounded-2xl shadow-2xl overflow-hidden">
        <%!-- Header --%>
        <div class="flex items-center justify-between px-4 py-3 border-b border-white/10">
          <span class="text-sm font-medium text-white">Notifications</span>
          <div class="flex items-center gap-2">
            <%= if length(@notifications) > 0 do %>
              <button phx-click="clear_all_notifications" class="text-xs text-white/40 hover:text-white/70 transition-colors cursor-pointer">
                Clear all
              </button>
            <% end %>
            <button phx-click="toggle_notifications_tray" class="p-1 hover:bg-white/10 rounded-full cursor-pointer">
              <svg class="w-4 h-4 text-white/60" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>
        </div>

        <%!-- Notification List --%>
        <div class="max-h-[60vh] overflow-y-auto scrollbar-hide">
          <%= if length(@notifications) > 0 do %>
            <%= for notification <- @notifications do %>
              <.notification_item notification={notification} />
            <% end %>
          <% else %>
            <div class="py-12 text-center text-white/30 text-sm">
              No notifications
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :notification, :map, required: true

  defp notification_item(assigns) do
    ~H"""
    <div
      class={"group flex items-start gap-3 px-4 py-3 border-b border-white/5 hover:bg-white/5 cursor-pointer transition-colors " <> if(@notification.read, do: "opacity-60", else: "")}
      phx-click="view_notification_item"
      phx-value-id={@notification.id}
    >
      <%!-- Avatar --%>
      <div class="shrink-0">
        <.notification_avatar notification={@notification} />
      </div>

      <%!-- Content --%>
      <div class="flex-1 min-w-0">
        <div class="flex items-center gap-2">
          <span class="text-sm font-medium text-white">@{@notification.actor_username}</span>
          <span class="text-xs text-white/30">{format_relative_time(@notification.timestamp)}</span>
        </div>
        <p class="text-xs text-white/60 truncate">{@notification.text}</p>
        <%= if @notification.count > 1 do %>
          <span class="text-[10px] text-blue-400">+{@notification.count - 1} more</span>
        <% end %>
      </div>

      <%!-- Dismiss button --%>
      <button
        phx-click="dismiss_notification_item"
        phx-value-id={@notification.id}
        phx-click-stop
        class="shrink-0 p-1 opacity-0 group-hover:opacity-100 hover:bg-white/10 rounded-full transition-opacity cursor-pointer"
      >
        <svg class="w-3 h-3 text-white/40" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
        </svg>
      </button>
    </div>
    """
  end

  attr :notification, :map, required: true

  defp notification_avatar(assigns) do
    ring_class = notification_type_ring(assigns.notification.type)
    assigns = assign(assigns, :ring_class, ring_class)

    ~H"""
    <div
      class={"w-8 h-8 rounded-full flex items-center justify-center text-white text-xs font-medium overflow-hidden " <> @ring_class}
      style={"background-color: #{@notification.actor_color};"}
    >
      <%= if @notification.actor_avatar_url do %>
        <img src={@notification.actor_avatar_url} class="w-full h-full object-cover" />
      <% else %>
        {String.slice(@notification.actor_username || "", 0, 2) |> String.upcase()}
      <% end %>
    </div>
    """
  end

  defp notification_type_ring(:message), do: ""
  defp notification_type_ring(:friend_request), do: "ring-2 ring-blue-400/50"
  defp notification_type_ring(:trust_request), do: "ring-2 ring-purple-400/50"
  defp notification_type_ring(:group_invite), do: "ring-2 ring-green-400/50"
  defp notification_type_ring(:connection_accepted), do: "ring-2 ring-emerald-400/50"
  defp notification_type_ring(:trust_confirmed), do: "ring-2 ring-purple-400/50"
  defp notification_type_ring(_), do: ""

  defp format_relative_time(timestamp) when is_nil(timestamp), do: ""
  defp format_relative_time(%NaiveDateTime{} = timestamp) do
    # Convert NaiveDateTime to DateTime for comparison
    {:ok, dt} = DateTime.from_naive(timestamp, "Etc/UTC")
    format_relative_time(dt)
  end
  defp format_relative_time(%DateTime{} = timestamp) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, timestamp, :second)
    cond do
      diff < 60 -> "now"
      diff < 3600 -> "#{div(diff, 60)}m"
      diff < 86400 -> "#{div(diff, 3600)}h"
      true -> "#{div(diff, 86400)}d"
    end
  end
end
