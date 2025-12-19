defmodule FriendsWeb.HomeLive.Components.SettingsComponents do
  use FriendsWeb, :html
  import FriendsWeb.HomeLive.Helpers

  # --- Settings Modal ---
  attr :show, :boolean, default: false
  attr :tab, :string, default: "profile"
  attr :current_user, :map, required: true
  attr :user_name, :string, default: nil
  attr :user_color, :string, default: nil
  attr :room_members, :list, default: []

  def settings_modal(assigns) do
    ~H"""
    <%= if @show do %>
      <div class="surface-overlay" style="z-index: 300;">
        <div class="absolute inset-0 bg-black/80 backdrop-blur-md animate-in fade-in duration-200" phx-click="close_settings_modal"></div>

        <div 
          id="settings-modal-container"
          class="surface-island aether-card w-full max-w-4xl h-[85vh] md:h-[80vh] flex flex-col shadow-[0_30px_100px_rgba(0,0,0,0.8)] rounded-t-[2rem] rounded-b-none lg:rounded-b-[2rem]"
          phx-window-keydown="close_settings_modal"
          phx-key="escape"
        >
          <div class="sheet-handle" phx-click="close_settings_modal"><div></div></div>
          
          <div class="flex flex-1 overflow-hidden">
              <!-- Sidebar -->
              <div class="w-20 md:w-48 border-r border-white/10 bg-white/5 flex flex-col">
                <div class="p-4 border-b border-white/5 hidden md:block">
                  <h2 class="font-bold text-white">Settings</h2>
                </div>
                
                <nav class="flex-1 p-2 space-y-1">
                  <button
                    phx-click="switch_settings_tab"
                    phx-value-tab="profile"
                    class={"w-full text-center md:text-left px-3 py-2 rounded-xl text-sm transition-colors #{if @tab == "profile", do: "bg-white/10 text-white font-medium", else: "text-white/50 hover:text-white hover:bg-white/5"}"}
                  >
                    <span class="md:hidden text-lg">👤</span>
                    <span class="hidden md:inline">Profile</span>
                  </button>
                  <button
                    phx-click="switch_settings_tab"
                    phx-value-tab="general"
                    class={"w-full text-center md:text-left px-3 py-2 rounded-xl text-sm transition-colors #{if @tab == "general", do: "bg-white/10 text-white font-medium", else: "text-white/50 hover:text-white hover:bg-white/5"}"}
                  >
                    <span class="md:hidden text-lg">⚙️</span>
                    <span class="hidden md:inline">General</span>
                  </button>
                </nav>
                
                <div class="p-2 border-t border-white/5">
                  <button
                    phx-click="sign_out"
                    class="w-full text-center md:text-left px-3 py-2 rounded-xl text-sm text-red-500 hover:bg-red-500/10 transition-colors flex items-center justify-center md:justify-start gap-2"
                  >
                    <span>🚪</span> <span class="hidden md:inline">Sign Out</span>
                  </button>
                </div>
              </div>

              <!-- Content Area -->
              <div class="flex-1 flex flex-col min-w-0 bg-black/40">
                <div class="flex items-center justify-between p-4 md:p-6 border-b border-white/10">
                  <h3 class="font-bold text-white text-lg md:text-xl capitalize">{@tab}</h3>
                  <button phx-click="close_settings_modal" class="text-white/30 hover:text-white">
                    <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M6 18L18 6M6 6l12 12" />
                    </svg>
                  </button>
                </div>

                <div class="flex-1 overflow-y-auto p-4 md:p-8 custom-scrollbar">
                  <%= case @tab do %>
                  <% "profile" -> %>
                    <div class="space-y-8">
                      <!-- Identity Card -->
                      <div class="aether-card p-6 rounded-xl bg-white/5 border border-white/10">
                        <div class="flex items-center gap-6">
                          <div
                            class="w-24 h-24 rounded-full flex items-center justify-center text-3xl font-bold text-black border-4 border-black shadow-lg"
                            style={"background-color: #{friend_color(@current_user)}"}
                          >
                            <%= if Map.get(@current_user, :avatar_url) do %>
                              <img src={@current_user.avatar_url} class="w-full h-full object-cover rounded-full" />
                            <% else %>
                              {String.first(@current_user.username)}
                            <% end %>
                          </div>
                          
                          <div class="flex-1">
                            <h4 class="text-xl font-bold text-white mb-1">@{@current_user.username}</h4>
                            <div class="text-sm text-white/50 font-mono bg-black/50 px-2 py-1 rounded inline-block">
                              User ID: {@current_user.id}
                            </div>
                          </div>
                        </div>
                      </div>

                      <!-- Name Edit -->
                      <div class="space-y-4">
                        <h4 class="text-sm font-bold uppercase tracking-wider text-white/40">Public Display Name</h4>
                        <div class="flex gap-3">
                          <div class="flex-1 relative">
                            <input 
                              type="text" 
                              value={@user_name || @current_user.display_name} 
                              class="w-full bg-white/5 border border-white/10 rounded-lg px-4 py-2 text-white placeholder-white/30 focus:border-white/30 focus:outline-none"
                              placeholder="Enter display name"
                              phx-blur="update_name_input"
                            />
                          </div>
                          <button class="btn-aether px-4 py-2">Save</button>
                        </div>
                        <p class="text-xs text-white/40">This name is visible to everyone in public spaces.</p>
                      </div>
                    </div>

                  <% "general" -> %>
                    <div class="space-y-6">
                      <div class="p-4 border border-blue-500/20 bg-blue-500/5 rounded-lg">
                        <h4 class="font-bold text-blue-400 mb-2">Application Info</h4>
                        <p class="text-sm text-white/70">Version 1.0.0 (Beta)</p>
                        <p class="text-sm text-white/70">Secure Context: <span class="text-green-400">Active</span></p>
                      </div>

                      <div class="space-y-4">
                        <h4 class="text-sm font-bold uppercase tracking-wider text-white/40">Interface</h4>
                        <label class="flex items-center justify-between p-3 rounded-lg hover:bg-white/5 cursor-pointer">
                          <span class="text-white">Reduced Motion</span>
                          <input type="checkbox" class="w-4 h-4 rounded bg-white/5 border-white/10 text-blue-500 focus:ring-blue-500/50" />
                        </label>
                      </div>
                    </div>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  # --- Network Modal ---
  attr :show, :boolean, default: false
  attr :tab, :string, default: "friends"
  attr :current_user, :map, required: true
  attr :friend_search, :string, default: ""
  attr :friend_search_results, :list, default: []
  attr :pending_requests, :list, default: []
  attr :friends, :list, default: []
  attr :trusted_friends, :list, default: []

  def network_modal(assigns) do
    ~H"""
    <%= if @show do %>
      <div class="surface-overlay" style="z-index: 200;">
        <div class="absolute inset-0 bg-black/80 backdrop-blur-md animate-in fade-in duration-200" phx-click="close_network_modal"></div>

        <div 
          class="surface-island aether-card w-full max-w-4xl h-[700px] rounded-t-[2rem] rounded-b-none lg:rounded-b-[2rem]"
          phx-window-keydown="close_network_modal"
          phx-key="escape"
        >
          <div class="sheet-handle" phx-click="close_network_modal"><div></div></div>
            
            <!-- Header -->
            <div class="p-6 border-b border-white/10 flex items-center justify-between bg-white/5">
              <div class="flex items-center gap-4">
                <div class="w-12 h-12 rounded-full bg-blue-500/20 flex items-center justify-center text-blue-400">
                  <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z" /></svg>
                </div>
                <div>
                  <h2 class="font-bold text-white text-xl tracking-tight">Network</h2>
                  <p class="text-xs text-white/30 font-medium font-mono uppercase tracking-widest mt-0.5">Manage connections</p>
                </div>
              </div>
              
              <button phx-click="close_network_modal" class="w-10 h-10 flex items-center justify-center rounded-full hover:bg-white/10 text-white/30 hover:text-white transition-colors">
                <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M6 18L18 6M6 6l12 12" /></svg>
              </button>
            </div>

            <!-- Tabs -->
            <div class="flex items-center gap-1 p-2 border-b border-white/10 bg-black/40">
              <button
                phx-click="switch_network_tab"
                phx-value-tab="friends"
                class={"px-4 py-2 rounded-xl text-sm font-medium transition-colors #{if @tab == "friends", do: "bg-white/10 text-white", else: "text-white/50 hover:text-white hover:bg-white/5"}"}
              >
                Friends
              </button>
              <button
                phx-click="switch_network_tab"
                phx-value-tab="requests"
                class={"px-4 py-2 rounded-xl text-sm font-medium transition-colors #{if @tab == "requests", do: "bg-white/10 text-white", else: "text-white/50 hover:text-white hover:bg-white/5"}"}
              >
                Requests <span class="bg-red-500 text-white text-[10px] px-1.5 rounded-full ml-1">{length(@pending_requests || [])}</span>
              </button>
              <button
                phx-click="switch_network_tab"
                phx-value-tab="search"
                class={"px-4 py-2 rounded-xl text-sm font-medium transition-colors #{if @tab == "search", do: "bg-white/10 text-white", else: "text-white/40 hover:text-white hover:bg-white/5"}"}
              >
                Find People
              </button>
            </div>

            <!-- Content -->
            <div class="flex-1 overflow-y-auto bg-black/20 p-6 custom-scrollbar">
              <%= case @tab do %>
                <% "friends" -> %>
                  <%= if @friends == [] do %>
                    <div class="flex flex-col items-center justify-center h-full text-center text-white/40">
                      <div class="w-16 h-16 bg-white/5/50 rounded-full flex items-center justify-center mb-4">
                        <svg class="w-8 h-8 opacity-50" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z" /></svg>
                      </div>
                      <h3 class="text-white font-medium mb-1">No friends yet</h3>
                      <p class="text-sm">Search for people to build your network.</p>
                      <button phx-click="switch_network_tab" phx-value-tab="search" class="mt-4 btn-aether btn-aether-primary px-4 py-2">Find Friends</button>
                    </div>
                  <% else %>
                    <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                      <%= for friend <- @friends do %>
                        <div class="aether-card p-4 rounded-xl border border-white/10 hover:border-white/20 transition-colors flex items-center gap-4">
                          <div class="w-12 h-12 rounded-full flex items-center justify-center font-bold text-black" style={"background-color: #{friend_color(friend)}"}>
                            {String.first(friend.username)}
                          </div>
                          <div>
                            <div class="font-bold text-white">@{friend.username}</div>
                            <div class="text-xs text-white/40">Connected</div>
                          </div>
                          <div class="ml-auto">
                            <button class="text-white/50 hover:text-white p-2">
                              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 5v.01M12 12v.01M12 19v.01M12 6a1 1 0 110-2 1 1 0 010 2zm0 7a1 1 0 110-2 1 1 0 010 2zm0 7a1 1 0 110-2 1 1 0 010 2z" /></svg>
                            </button>
                          </div>
                        </div>
                      <% end %>
                    </div>
                  <% end %>

                <% "requests" -> %>
                  <%= if @pending_requests == [] do %>
                    <div class="flex flex-col items-center justify-center h-full text-center text-white/40">
                      <p>No pending friend requests.</p>
                    </div>
                  <% else %>
                    <div class="space-y-4">
                      <%= for req <- @pending_requests do %>
                        <div class="aether-card p-4 rounded-xl border border-white/10 flex items-center gap-4">
                          <div class="w-12 h-12 rounded-full bg-white/5 flex items-center justify-center font-bold text-white">?</div>
                          <div class="flex-1">
                            <div class="font-bold text-white">Request from User #{req.user_id}</div>
                            <div class="text-xs text-white/40">Wants to be your friend</div>
                          </div>
                          <div class="flex gap-2">
                            <button class="px-3 py-1.5 rounded bg-green-500/20 text-green-400 hover:bg-green-500/30 text-sm font-medium">Accept</button>
                            <button class="px-3 py-1.5 rounded bg-red-500/20 text-red-400 hover:bg-red-500/30 text-sm font-medium">Ignore</button>
                          </div>
                        </div>
                      <% end %>
                    </div>
                  <% end %>

                <% "search" -> %>
                  <div class="max-w-xl mx-auto space-y-6">
                    <form phx-submit="search_friends" phx-change="search_friends">
                      <div class="relative">
                        <input
                          type="text"
                          name="query"
                          value={@friend_search}
                          placeholder="Search be username..."
                          class="w-full bg-white/5 border border-white/10 rounded-xl px-5 py-3 pl-12 text-white placeholder-white/30 focus:border-blue-500 focus:outline-none"
                          autocomplete="off"
                        />
                        <svg class="absolute left-4 top-1/2 -translate-y-1/2 w-5 h-5 text-white/40" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
                        </svg>
                      </div>
                    </form>

                    <%= if @friend_search != "" and @friend_search_results != [] do %>
                      <div class="space-y-2">
                        <div class="text-xs font-bold uppercase tracking-wider text-white/40 mb-2">Results</div>
                        <%= for user <- @friend_search_results do %>
                          <div class="flex items-center justify-between p-3 rounded-xl bg-white/5 border border-white/5">
                            <div class="flex items-center gap-3">
                              <div class="w-10 h-10 rounded-full flex items-center justify-center text-black font-bold" style={"background-color: #{friend_color(user)}"}>
                                {String.first(user.username)}
                              </div>
                              <span class="text-white font-medium">@{user.username}</span>
                            </div>
                            <button class="text-blue-400 hover:text-white text-sm font-medium">Add Friend</button>
                          </div>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
              <% end %>
            </div>
          </div>
        </div>
    <% end %>
    """
  end

  # --- Devices Modal ---
  attr :show, :boolean, default: false
  attr :devices, :list, default: []
  attr :current_device_id, :string, default: nil

  def devices_modal(assigns) do
    ~H"""
    <%= if @show do %>
      <div class="surface-overlay" style="z-index: 200;">
        <div class="absolute inset-0 bg-black/80 backdrop-blur-md animate-in fade-in duration-200" phx-click="close_devices_modal"></div>

        <div 
          class="surface-island aether-card w-full max-w-2xl max-h-[80vh] rounded-t-[2rem] rounded-b-none lg:rounded-b-[2rem]"
          phx-window-keydown="close_devices_modal"
          phx-key="escape"
        >
          <div class="sheet-handle" phx-click="close_devices_modal"><div></div></div>
            
            <!-- Header -->
            <div class="p-8 border-b border-white/10 flex items-center justify-between bg-white/5">
              <div class="flex items-center gap-6">
                <div class="w-14 h-14 rounded-full bg-purple-500/20 flex items-center justify-center text-purple-400">
                  <svg class="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M12 18h.01M8 21h8a2 2 0 002-2V5a2 2 0 00-2-2H8a2 2 0 00-2 2v14a2 2 0 002 2z" /></svg>
                </div>
                <div>
                  <h2 class="font-bold text-white text-2xl tracking-tight">Devices</h2>
                  <p class="text-xs text-white/30 font-medium font-mono uppercase tracking-widest mt-0.5">Manage active sessions</p>
                </div>
              </div>
              
              <button phx-click="close_devices_modal" class="w-10 h-10 flex items-center justify-center rounded-full hover:bg-white/10 text-white/30 hover:text-white transition-colors cursor-pointer">
                <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M6 18L18 6M6 6l12 12" /></svg>
              </button>
            </div>

            <!-- Content -->
            <div class="flex-1 overflow-y-auto p-8 custom-scrollbar">
              <div class="space-y-4">
                <%= if @devices == [] do %>
                  <div class="text-center py-12 text-white/40">
                    <p>No other devices found.</p>
                  </div>
                <% else %>
                  <%= for device <- @devices do %>
                    <div class={[
                       "aether-card p-4 rounded-xl border flex items-center gap-4 transition-colors",
                       # Highlight current device if ID matches (logic needs to be robust, using fingerprint usually)
                       # For now just list them.
                       "border-white/10 bg-white/5"
                    ]}>
                      <div class="w-10 h-10 rounded-lg bg-white/5 flex items-center justify-center text-white/50">
                        <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9.75 17L9 20l-1 1h8l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" /></svg>
                      </div>
                      
                      <div class="flex-1">
                        <div class="flex items-center gap-2">
                          <h4 class="font-bold text-white">{device.device_name || "Unknown Device"}</h4>
                          <%= if device.trusted do %>
                             <span class="text-[10px] bg-green-500/20 text-green-400 px-1.5 py-0.5 rounded border border-green-500/30">Trusted</span>
                          <% end %>
                        </div>
                        <div class="text-xs text-white/40 font-mono mt-0.5">
                          {device.device_fingerprint |> String.slice(0, 8)}...
                        </div>
                        <div class="text-xs text-white/50 mt-1">
                          Last seen: {Calendar.strftime(device.last_seen_at, "%b %d, %H:%M")}
                        </div>
                      </div>
                      
                      <button 
                         class="text-red-400 hover:text-red-300 text-xs font-bold uppercase tracking-wider px-3 py-1.5 hover:bg-red-500/10 rounded transition-colors cursor-pointer"
                         phx-click="revoke_device"
                         phx-value-id={device.id}
                         data-confirm="Are you sure you want to revoke this device? It will be logged out."
                      >
                        Revoke
                      </button>
                    </div>
                  <% end %>
                <% end %>
              </div>
              
              <div class="mt-8 p-4 rounded-xl bg-blue-500/10 border border-blue-500/20">
                <div class="flex items-start gap-3">
                  <span class="text-blue-400">ℹ️</span>
                  <div class="text-sm text-white/70">
                    <p class="font-bold text-blue-400 mb-1">Security Note</p>
                    <p>Revoking a device will invalidate its access tokens. If you suspect unauthorized access, revoke the device and rotate your keys.</p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    <% end %>
    """
  end
end
