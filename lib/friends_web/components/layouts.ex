defmodule FriendsWeb.Layouts do
  @moduledoc """
  Layout components for Friends app.
  """
  use FriendsWeb, :html

  embed_templates "layouts/*"

  @doc """
  Renders the shared app header.
  This is used in the app layout to provide consistent navigation.
  Events bubble up to the parent LiveView.
  """
  attr :current_user, :any, default: nil
  attr :user_color, :string, default: "#888"
  attr :auth_status, :atom, default: :pending
  attr :page_title, :string, default: "Friends"
  attr :room, :any, default: nil
  attr :viewers, :list, default: []
  attr :user_rooms, :list, default: []
  attr :public_rooms, :list, default: []
  attr :pending_count, :integer, default: 0
  attr :recovery_count, :integer, default: 0
  attr :show_header_dropdown, :boolean, default: false
  attr :show_user_dropdown, :boolean, default: false
  attr :current_route, :string, default: "/"


  def shared_header(assigns) do
    # Determine what to show in the space selector
    space_label = cond do
      assigns[:room] && assigns[:room].code == "lobby" -> "Public Square"
      assigns[:room] -> assigns[:room].name || assigns[:room].code
      true -> "Spaces"
    end
    assigns = Phoenix.Component.assign(assigns, :space_label, space_label)

    ~H"""
    <header class="glass-strong border-b border-white/5 sticky top-0 z-40">
      <div class="max-w-[1600px] mx-auto px-4 sm:px-8 py-4">
        <div class="flex items-center justify-between gap-6">
          <%!-- Space selector / Navigation --%>
          <div class="relative" phx-click-away="close_header_dropdown">
            <button
              type="button"
              phx-click="toggle_header_dropdown"
              class="flex items-center gap-3 text-base hover:text-white transition-all cursor-pointer group"
            >
              <%= if @room && @room.is_private do %>
                <span class="text-emerald-400 text-lg">🔒</span>
              <% else %>
                <div class="w-3 h-3 rounded-full bg-blue-400 presence-dot"></div>
              <% end %>
              <span class="font-medium tracking-wide">{@space_label}</span>
              <span class="text-neutral-500 text-sm group-hover:text-neutral-300 transition-colors">▼</span>
            </button>

            <%= if @show_header_dropdown do %>
              <div class="absolute top-10 left-0 w-72 bg-neutral-900 border border-white/10 rounded-xl shadow-xl overflow-hidden z-50">
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
                
                <%!-- User dropdown --%>
                <div class="relative" phx-click-away="close_user_dropdown">
                  <button
                    type="button"
                    phx-click="toggle_user_dropdown"
                    class="flex items-center gap-3 text-sm hover:text-white transition-all cursor-pointer px-4 py-2 rounded-full glass border border-white/10 hover:border-white/20 relative"
                  >
                    <div
                      class="w-3 h-3 rounded-full presence-dot"
                      style={"background-color: #{@user_color || "#666"}"}
                    />
                    <span class="text-neutral-200">@{@current_user.username}</span>
                    <span class="text-neutral-500 text-xs">▼</span>
                    <%= if @recovery_count > 0 do %>
                      <span class="absolute -top-1 -right-1 w-4 h-4 bg-red-500 text-white text-[10px] font-bold rounded-full flex items-center justify-center">
                        !
                      </span>
                    <% end %>
                  </button>

                  <%= if @show_user_dropdown do %>
                    <div class="absolute top-12 right-0 w-56 bg-neutral-900 border border-white/10 rounded-xl shadow-xl overflow-hidden z-50">
                      <div class="p-3 border-b border-white/5">
                        <div class="flex items-center gap-3">
                          <div
                            class="w-10 h-10 rounded-full"
                            style={"background: linear-gradient(135deg, #{@user_color} 0%, #{@user_color}88 100%)"}
                          />
                          <div>
                            <div class="text-sm font-medium text-white">{@current_user.display_name || @current_user.username}</div>
                            <div class="text-xs text-neutral-500">@{@current_user.username}</div>
                          </div>
                        </div>
                      </div>
                      
                      <div class="p-2 space-y-1">
                        <%= if @recovery_count > 0 do %>
                          <div class="px-3 py-2 bg-red-500/10 rounded-lg border border-red-500/20 mb-2">
                            <div class="text-xs text-red-400 font-medium">🚨 {@recovery_count} friend(s) need recovery help</div>
                          </div>
                        <% end %>
                        
                        <.link navigate={~p"/network"} class={"flex items-center gap-3 px-3 py-2 rounded-lg text-sm transition-colors cursor-pointer #{if @current_route == "/network", do: "bg-neutral-800 text-white", else: "text-neutral-300 hover:bg-white/5 hover:text-white"}"} >
                          <span>👥</span> Network
                          <%= if @pending_count > 0 do %>
                            <span class="ml-auto px-1.5 py-0.5 bg-blue-500 text-black text-[10px] font-bold rounded-full">{@pending_count}</span>
                          <% end %>
                        </.link>
                        
                        <.link navigate={~p"/devices"} class="flex items-center gap-3 px-3 py-2 rounded-lg text-sm text-neutral-300 hover:bg-white/5 hover:text-white transition-colors cursor-pointer">
                          <span>🔐</span> Devices
                        </.link>
                        
                        <div class="h-px bg-white/5 my-1"></div>
                        
                        <button phx-click="sign_out" class="w-full flex items-center gap-3 px-3 py-2 rounded-lg text-sm text-red-400 hover:bg-red-500/10 hover:text-red-300 transition-colors cursor-pointer">
                          <span>🚪</span> Sign out
                        </button>
                      </div>
                    </div>
                  <% end %>
                </div>
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

  @doc """
  Renders flash messages.
  """
  attr :flash, :map, required: true
  attr :kind, :atom, values: [:info, :error], default: :info
  attr :rest, :global

  def flash(assigns) do
    ~H"""
    <div
      :if={msg = Phoenix.Flash.get(@flash, @kind)}
      id={"flash-#{@kind}"}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> JS.hide(to: "#flash-#{@kind}")}
      role="alert"
      class={[
        "fixed top-4 right-4 z-[70] px-4 py-3 text-sm cursor-pointer",
        @kind == :info && "bg-neutral-900 text-white",
        @kind == :error && "bg-red-600 text-white"
      ]}
      {@rest}
    >
      {msg}
    </div>
    """
  end

  @doc """
  Renders all flash messages.
  """
  attr :flash, :map, required: true

  def flash_group(assigns) do
    ~H"""
    <.flash kind={:info} flash={@flash} />
    <.flash kind={:error} flash={@flash} />
    """
  end
end

