defmodule FriendsWeb.HeaderComponent do
  @moduledoc """
  Shared header component for consistent navigation across all pages.
  """
  use FriendsWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <header class="glass-strong border-b border-white/5 sticky top-0 z-40">
      <div class="max-w-[1600px] mx-auto px-4 sm:px-8 py-4">
        <div class="flex items-center justify-between gap-6">
          <%!-- Space selector / Navigation --%>
          <div class="relative" phx-click-away="close_header_dropdown">
            <button
              type="button"
              phx-click="toggle_header_dropdown"
              phx-target={@myself}
              class="flex items-center gap-3 text-base hover:text-white transition-all cursor-pointer group"
            >
              <%= if @room && @room.is_private do %>
                <span class="text-emerald-400 text-lg">🔒</span>
              <% else %>
                <div class="w-3 h-3 rounded-full bg-blue-400 presence-dot"></div>
              <% end %>
              <span class="font-medium tracking-wide">{@page_title}</span>
              <span class="text-neutral-500 text-sm group-hover:text-neutral-300 transition-colors">▼</span>
            </button>

            <%= if @show_dropdown do %>
              <div class="absolute top-10 left-0 w-72 bg-neutral-900 border border-white/10 rounded-xl shadow-xl overflow-hidden z-50 animate-in fade-in zoom-in-95 duration-100">
                <div class="p-2 space-y-1 max-h-[80vh] overflow-y-auto">
                  <%!-- Public Square --%>
                  <.link navigate={~p"/r/lobby"} class={"flex items-center gap-3 px-3 py-2 rounded-lg text-sm transition-colors cursor-pointer #{if @current_route == "/r/lobby", do: "bg-neutral-800 text-white", else: "text-neutral-300 hover:bg-white/5 hover:text-white"}"}>
                    <span>🏙️</span> Public Square
                  </.link>
                  
                  <%= if @current_user do %>
                    <%!-- My Spaces --%>
                    <%= if @user_rooms != [] do %>
                      <div class="h-px bg-white/5 my-1"></div>
                      <div class="px-3 py-1.5 text-xs font-medium text-neutral-500 uppercase tracking-wider">My Spaces</div>
                      <%= for room <- @user_rooms do %>
                         <.link navigate={~p"/r/#{room.code}"} class={"w-full flex items-center gap-3 px-3 py-2 rounded-lg text-sm transition-colors text-left group cursor-pointer #{if @room && @room.code == room.code, do: "bg-neutral-800 text-white", else: "text-neutral-300 hover:bg-white/5 hover:text-white"}"}>
                           <span>🔒</span>
                           <span class="truncate">{if(room.name && room.name != "", do: room.name, else: room.code)}</span>
                         </.link>
                      <% end %>
                    <% end %>

                    <%!-- Public Spaces --%>
                    <%= if @public_rooms != [] do %>
                      <div class="h-px bg-white/5 my-1"></div>
                      <div class="px-3 py-1.5 text-xs font-medium text-neutral-500 uppercase tracking-wider">Public Spaces</div>
                      <%= for room <- @public_rooms do %>
                         <%= if room.code != "lobby" do %>
                           <.link navigate={~p"/r/#{room.code}"} class={"w-full flex items-center gap-3 px-3 py-2 rounded-lg text-sm transition-colors text-left group cursor-pointer #{if @room && @room.code == room.code, do: "bg-neutral-800 text-white", else: "text-neutral-300 hover:bg-white/5 hover:text-white"}"}>
                             <span>🌐</span>
                             <div class="flex-1 min-w-0">
                               <div class="truncate">{if(room.name && room.name != "", do: room.name, else: room.code)}</div>
                             </div>
                           </.link>
                         <% end %>
                      <% end %>
                    <% end %>
                    
                    <%!-- Actions --%>
                    <div class="h-px bg-white/5 my-1"></div>
                    <button phx-click="open_room_modal" class="w-full flex items-center gap-3 px-3 py-2 rounded-lg hover:bg-white/5 text-sm text-emerald-400 hover:text-emerald-300 transition-colors text-left cursor-pointer">
                       <span>✨</span> Create / Join Space
                    </button>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>

          <%!-- Identity + Viewers --%>
          <div class="flex items-center gap-6">
            <%!-- Viewers with opal glow --%>
            <%= if @viewers && @viewers != [] do %>
            <div class="hidden sm:flex items-center gap-2">
                <%= for {viewer, idx} <- Enum.with_index(Enum.take(@viewers, 5)) do %>
                  <div
                    class="w-2.5 h-2.5 rounded-full presence-dot"
                    style={"background-color: #{viewer.user_color}; opacity: #{1 - idx * 0.12}"}
                    title={viewer.user_name || "anonymous"}
                  />
                <% end %>
                <span class="text-sm text-neutral-500 ml-2">{length(@viewers)} here</span>
              </div>
            <% end %>

            <%!-- User identity --%>
            <%= if @auth_status == :pending do %>
              <span class="text-sm text-neutral-500">checking identity…</span>
            <% else %>
              <%= if @current_user do %>
                <.link
                  navigate={~p"/messages"}
                  class="flex items-center gap-2 text-sm hover:text-white transition-all cursor-pointer px-4 py-2 rounded-full glass border border-white/10 hover:border-white/20"
                >
                  <span>💬</span>
                  <span class="hidden sm:inline">Messages</span>
                </.link>
                <.link
                  navigate={~p"/network"}
                  class="flex items-center gap-2 text-sm hover:text-white transition-all cursor-pointer px-4 py-2 rounded-full glass border border-white/10 hover:border-white/20 relative"
                >
                  <span>👥</span>
                  <span class="hidden sm:inline">Network</span>
                  <%= if @pending_count && @pending_count > 0 do %>
                    <span class="absolute -top-1 -right-1 w-4 h-4 bg-blue-500 text-black text-[10px] font-bold rounded-full flex items-center justify-center">
                      {@pending_count}
                    </span>
                  <% end %>
                </.link>
                <button
                  type="button"
                  phx-click="open_settings_modal"
                  class="flex items-center gap-3 text-sm hover:text-white transition-all cursor-pointer px-4 py-2 rounded-full glass border border-white/10 hover:border-white/20"
                >
                  <div
                    class="w-3 h-3 rounded-full presence-dot"
                    style={"background-color: #{@user_color || "#666"}"}
                  />
                  <span class="text-neutral-200">@{@current_user.username}</span>
                </button>
              <% else %>
                <div class="flex items-center gap-2">
                  <a
                    href="/login"
                    class="flex items-center gap-2 text-sm text-neutral-400 hover:text-white transition-all px-4 py-2 rounded-full glass border border-white/5 hover:border-white/15"
                  >
                    <span>Login</span>
                  </a>
                  <a
                    href="/register"
                    class="flex items-center gap-2 text-sm px-4 py-2 rounded-full btn-opal"
                  >
                    <span class="opal-text font-medium">Create Account</span>
                  </a>
                </div>
              <% end %>
            <% end %>
          </div>
        </div>
      </div>
    </header>
    """
  end

  @impl true
  def handle_event("toggle_header_dropdown", _, socket) do
    {:noreply, assign(socket, :show_dropdown, !socket.assigns.show_dropdown)}
  end

  @impl true
  def handle_event("close_header_dropdown", _, socket) do
    {:noreply, assign(socket, :show_dropdown, false)}
  end
end
