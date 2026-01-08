defmodule FriendsWeb.HomeLive.Components.SettingsComponents do
  use FriendsWeb, :html
  import FriendsWeb.HomeLive.Helpers

  # --- Settings Sheet (Fluid Design) ---
  attr :show, :boolean, default: false
  attr :current_user, :map, required: true
  attr :user_name, :string, default: nil
  attr :devices, :list, default: []

  def settings_modal(assigns) do
    ~H"""
    <%= if @show do %>
      <div id="settings-sheet" class="fixed inset-0 z-[200]" phx-hook="LockScroll">
        <%!-- Backdrop --%>
        <div
          class="absolute inset-0 bg-black/60 backdrop-blur-sm animate-in fade-in duration-200"
          phx-click="close_settings_modal"
        ></div>

        <%!-- Sheet --%>
        <div class="absolute inset-x-0 bottom-0 z-10 flex justify-center animate-in slide-in-from-bottom duration-300 pointer-events-none">
          <div 
            id="settings-sheet-content"
            class="w-full max-w-lg bg-neutral-900/95 backdrop-blur-xl border-t border-x border-white/10 rounded-t-3xl shadow-2xl max-h-[85vh] flex flex-col pointer-events-auto"
            phx-window-keydown="close_settings_modal"
            phx-key="escape"
            phx-hook="SwipeableDrawer"
            data-close-event="close_settings_modal"
          >
            <%!-- Handle --%>
            <div class="py-3 flex justify-center cursor-pointer" phx-click="close_settings_modal">
              <div class="w-10 h-1 rounded-full bg-white/20"></div>
            </div>

            <%!-- User Header --%>
            <div class="px-6 pb-4 border-b border-white/10">
              <div class="flex items-center gap-4">
                <div
                  class="w-16 h-16 rounded-full flex items-center justify-center text-2xl font-bold border-2 border-white/10"
                  style={"background: linear-gradient(135deg, #{friend_color(@current_user)} 0%, #{friend_color(@current_user)}dd 100%);"}
                >
                  <%= if Map.get(@current_user, :avatar_url) do %>
                    <img src={@current_user.avatar_url} class="w-full h-full object-cover rounded-full" alt="Avatar" />
                  <% else %>
                    <span class="text-white">{String.first(@current_user.username) |> String.upcase()}</span>
                  <% end %>
                </div>
                <div class="flex-1 min-w-0">
                  <h3 class="text-lg font-bold text-white truncate">@{@current_user.username}</h3>
                  <p class="text-xs text-white/40">Online</p>
                </div>
              </div>
            </div>

            <%!-- Settings Content --%>
            <div class="flex-1 overflow-y-auto">
              <%!-- Account Section --%>
              <div class="px-4 py-4">
                <h4 class="text-xs font-semibold text-white/40 uppercase tracking-wider px-2 mb-2">Account</h4>
                <div class="bg-white/5 border border-white/10 rounded-2xl overflow-hidden">
                  <%!-- Display Name Row --%>
                  <div class="flex items-center gap-3 px-4 py-3 hover:bg-white/5 transition-colors">
                    <div class="w-8 h-8 rounded-full bg-white/10 flex items-center justify-center flex-shrink-0">
                      <svg class="w-4 h-4 text-white/70" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
                      </svg>
                    </div>
                    <div class="flex-1 min-w-0">
                      <div class="text-sm text-white/90">Display Name</div>
                      <div class="text-xs text-white/50 truncate">{@user_name || @current_user.display_name || "Not set"}</div>
                    </div>
                    <button class="text-blue-400 text-sm font-medium cursor-pointer hover:text-blue-300">
                      Edit
                    </button>
                  </div>

                  <%!-- Devices Row --%>
                  <div class="border-t border-white/10"></div>
                  <button
                    phx-click={JS.push("close_settings_modal") |> JS.push("open_profile_sheet")}
                    class="w-full flex items-center gap-3 px-4 py-3 hover:bg-white/5 transition-colors cursor-pointer"
                  >
                    <div class="w-8 h-8 rounded-full bg-white/10 flex items-center justify-center flex-shrink-0">
                      <svg class="w-4 h-4 text-white/70" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M12 18h.01M8 21h8a2 2 0 002-2V5a2 2 0 00-2-2H8a2 2 0 00-2 2v14a2 2 0 002 2z" />
                      </svg>
                    </div>
                    <div class="flex-1 text-left">
                      <div class="text-sm text-white/90">Devices & Settings</div>
                      <div class="text-xs text-white/50">{length(@devices)} connected</div>
                    </div>
                    <svg class="w-4 h-4 text-white/30" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
                    </svg>
                  </button>

                  <%!-- User ID Row --%>
                  <div class="border-t border-white/10"></div>
                  <div class="flex items-center gap-3 px-4 py-3">
                    <div class="w-8 h-8 rounded-full bg-white/10 flex items-center justify-center flex-shrink-0">
                      <svg class="w-4 h-4 text-white/70" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M7 20l4-16m2 16l4-16M6 9h14M4 15h14" />
                      </svg>
                    </div>
                    <div class="flex-1 min-w-0">
                      <div class="text-sm text-white/90">User ID</div>
                      <div class="text-xs text-white/50 font-mono truncate">{@current_user.id}</div>
                    </div>
                  </div>
                </div>
              </div>

              <%!-- Your Network Section --%>
              <div class="px-4 py-4">
                <h4 class="text-xs font-semibold text-white/40 uppercase tracking-wider px-2 mb-2">Your Network</h4>
                <div class="bg-white/5 border border-white/10 rounded-2xl overflow-hidden">
                  <button
                    phx-click={JS.push("close_settings_modal") |> JS.push("show_my_constellation")}
                    class="w-full flex items-center gap-3 px-4 py-3 hover:bg-white/5 transition-colors cursor-pointer"
                  >
                    <div class="w-8 h-8 rounded-full bg-white/10 flex items-center justify-center flex-shrink-0">
                      <svg class="w-4 h-4 text-white/70" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <%!-- Constellation/network graph icon --%>
                        <circle cx="12" cy="5" r="2" stroke-width="1.5" />
                        <circle cx="6" cy="17" r="2" stroke-width="1.5" />
                        <circle cx="18" cy="17" r="2" stroke-width="1.5" />
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M12 7v5M8.5 15.5L11 12M15.5 15.5L13 12" />
                      </svg>
                    </div>
                    <div class="flex-1 text-left">
                      <div class="text-sm text-white/90">Your Network</div>
                      <div class="text-xs text-white/50">Your personal network</div>
                    </div>
                    <svg class="w-5 h-5 text-white/30" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
                    </svg>
                  </button>

                  <div class="border-t border-white/10"></div>

                  <button
                    phx-click={JS.push("close_settings_modal") |> JS.push("show_welcome_graph")}
                    class="w-full flex items-center gap-3 px-4 py-3 hover:bg-white/5 transition-colors cursor-pointer"
                  >
                    <div class="w-8 h-8 rounded-full bg-white/10 flex items-center justify-center flex-shrink-0">
                      <svg class="w-4 h-4 text-white/70" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <%!-- Globe/global network icon --%>
                        <circle cx="12" cy="12" r="10" stroke-width="1.5" />
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M2 12h20M12 2a15.3 15.3 0 014 10 15.3 15.3 0 01-4 10 15.3 15.3 0 01-4-10 15.3 15.3 0 014-10z" />
                      </svg>
                    </div>
                    <div class="flex-1 text-left">
                      <div class="text-sm text-white/90">Global Network</div>
                      <div class="text-xs text-white/50">Everyone on the platform</div>
                    </div>
                    <svg class="w-5 h-5 text-white/30" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
                    </svg>
                  </button>
                </div>
              </div>

              <%!-- About Section --%>
              <div class="px-4 py-4">
                <h4 class="text-xs font-semibold text-white/40 uppercase tracking-wider px-2 mb-2">About</h4>
                <div class="bg-white/5 border border-white/10 rounded-2xl overflow-hidden">
                  <div class="flex items-center gap-3 px-4 py-3">
                    <div class="w-8 h-8 rounded-full bg-white/10 flex items-center justify-center flex-shrink-0">
                      <svg class="w-4 h-4 text-white/70" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                      </svg>
                    </div>
                    <div class="flex-1">
                      <div class="text-sm text-white/90">Version</div>
                      <div class="text-xs text-white/50">1.0.0 Beta</div>
                    </div>
                  </div>
                </div>
              </div>

              <%!-- Sign Out Button --%>
              <div class="px-4 py-6">
                <button
                  phx-click="sign_out"
                  class="w-full py-3 px-4 rounded-xl bg-red-500/10 hover:bg-red-500/20 text-red-400 hover:text-red-300 font-medium transition-colors cursor-pointer"
                >
                  Sign Out
                </button>
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
                People
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
                      <h3 class="text-white font-medium mb-1">No people yet</h3>
                      <p class="text-sm">Search for people to build your network.</p>
                      <button phx-click="switch_network_tab" phx-value-tab="search" class="mt-4 btn-aether btn-aether-primary px-4 py-2">Find People</button>
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
                      <p>No pending requests.</p>
                    </div>
                  <% else %>
                    <div class="space-y-4">
                      <%= for req <- @pending_requests do %>
                        <div class="aether-card p-4 rounded-xl border border-white/10 flex items-center gap-4">
                          <div class="w-12 h-12 rounded-full bg-white/5 flex items-center justify-center font-bold text-white">?</div>
                          <div class="flex-1">
                            <div class="font-bold text-white">Request from User #{req.user_id}</div>
                            <div class="text-xs text-white/40">Wants to connect</div>
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
                            <button class="text-blue-400 hover:text-white text-sm font-medium">Connect</button>
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
end
