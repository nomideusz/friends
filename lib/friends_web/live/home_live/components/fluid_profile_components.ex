defmodule FriendsWeb.HomeLive.Components.FluidProfileComponents do
  @moduledoc """
  Fluid design profile and settings components.
  Simple bottom sheet for user profile and settings.
  """
  use FriendsWeb, :html
  import FriendsWeb.HomeLive.Helpers

  # ============================================================================
  # PROFILE SHEET
  # Bottom sheet for viewing profile and settings
  # ============================================================================

  attr :show, :boolean, default: false
  attr :current_user, :map, required: true
  attr :devices, :list, default: []
  attr :uploads, :map, default: nil

  def profile_sheet(assigns) do
    ~H"""
    <%= if @show do %>
      <div id="profile-sheet" class="fixed inset-0 z-[200]" phx-hook="LockScroll" phx-window-keydown="close_profile_sheet" phx-key="escape">
        <%!-- Backdrop --%>
        <div
          class="absolute inset-0 bg-black/70 backdrop-blur-sm animate-in fade-in duration-200"
          phx-click="close_profile_sheet"
        ></div>

        <%!-- Sheet --%>
        <div class="absolute inset-x-0 bottom-0 z-10 flex justify-center animate-in slide-in-from-bottom duration-300 pointer-events-none">
          <div
            id="profile-sheet-content"
            class="w-full max-w-lg bg-neutral-900/95 backdrop-blur-xl border-t border-x border-white/10 rounded-t-3xl shadow-2xl max-h-[85vh] flex flex-col pointer-events-auto"
            phx-click-away="close_profile_sheet"
            phx-hook="SwipeableDrawer"
            data-close-event="close_profile_sheet"
          >
            <%!-- Handle --%>
            <div class="py-3 flex justify-center cursor-pointer" phx-click="close_profile_sheet">
              <div class="w-10 h-1 rounded-full bg-white/20"></div>
            </div>

            <%!-- Profile Header --%>
            <div class="px-6 pb-6">
              <div class="flex items-center gap-4">
                <%!-- Avatar with Upload --%>
                <form phx-change="validate_avatar" phx-submit="upload_avatar" class="relative flex-shrink-0">
                  <label class="relative block cursor-pointer group">
                    <div
                      class="w-16 h-16 rounded-full flex items-center justify-center text-2xl font-bold text-black border-2 border-white/10 shadow-lg overflow-hidden"
                      style={"background-color: #{friend_color(@current_user)}"}
                    >
                      <%= if Map.get(@current_user, :avatar_url) do %>
                        <img src={@current_user.avatar_url} class="w-full h-full object-cover" alt="Avatar" />
                      <% else %>
                        {String.first(@current_user.username) |> String.upcase()}
                      <% end %>
                    </div>

                    <%!-- Upload overlay --%>
                    <div class="absolute inset-0 rounded-full bg-black/60 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center">
                      <svg class="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 9a2 2 0 012-2h.93a2 2 0 001.664-.89l.812-1.22A2 2 0 0110.07 4h3.86a2 2 0 011.664.89l.812 1.22A2 2 0 0018.07 7H19a2 2 0 012 2v9a2 2 0 01-2 2H5a2 2 0 01-2-2V9z" />
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 13a3 3 0 11-6 0 3 3 0 016 0z" />
                      </svg>
                    </div>

                    <%= if @uploads && @uploads[:avatar] do %>
                      <.live_file_input upload={@uploads.avatar} class="sr-only" />
                    <% end %>
                  </label>
                </form>

                <%!-- User Info --%>
                <div class="flex-1 min-w-0">
                  <h2 class="text-xl font-bold text-white truncate">@{@current_user.username}</h2>
                  <p class="text-xs text-white/40 font-mono">ID: {@current_user.id}</p>
                </div>
              </div>
            </div>

            <%!-- Content --%>
            <div class="flex-1 overflow-y-auto px-4 pb-4 space-y-3">
              <%!-- Account Section --%>
              <div>
                <h3 class="text-[10px] font-bold text-white/40 uppercase tracking-widest px-3 mb-2">Account</h3>
                <div class="space-y-1">
                  <%!-- Devices --%>
                  <button
                    phx-click="open_devices_modal"
                    class="w-full flex items-center justify-between p-3 rounded-xl bg-white/5 hover:bg-white/10 border border-white/5 hover:border-white/10 transition-all group"
                  >
                    <div class="flex items-center gap-3">
                      <div class="w-8 h-8 rounded-lg bg-white/5 flex items-center justify-center">
                        <svg class="w-4 h-4 text-white/70" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 18h.01M8 21h8a2 2 0 002-2V5a2 2 0 00-2-2H8a2 2 0 00-2 2v14a2 2 0 002 2z" />
                        </svg>
                      </div>
                      <div class="text-left">
                        <div class="text-sm font-medium text-white">Devices</div>
                        <div class="text-xs text-white/40">{length(@devices)} connected</div>
                      </div>
                    </div>
                    <svg class="w-4 h-4 text-white/30 group-hover:text-white/50 transition-colors" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
                    </svg>
                  </button>

                  <%!-- Add Device (Pairing) --%>
                  <button
                    phx-click="create_pairing_token"
                    class="w-full flex items-center justify-between p-3 rounded-xl bg-gradient-to-r from-blue-500/10 to-purple-500/10 hover:from-blue-500/20 hover:to-purple-500/20 border border-blue-500/20 hover:border-blue-500/30 transition-all group"
                  >
                    <div class="flex items-center gap-3">
                      <div class="w-8 h-8 rounded-lg bg-blue-500/20 flex items-center justify-center">
                        <svg class="w-4 h-4 text-blue-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
                        </svg>
                      </div>
                      <div class="text-left">
                        <div class="text-sm font-medium text-white">Add Device</div>
                        <div class="text-xs text-white/40">Link another phone or laptop</div>
                      </div>
                    </div>
                    <svg class="w-4 h-4 text-blue-400/50 group-hover:text-blue-400 transition-colors" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v1m6 11h2m-6 0h-2v4m0-11v3m0 0h.01M12 12h4.01M16 20h4M4 12h4m12 0h.01M5 8h2a1 1 0 001-1V5a1 1 0 00-1-1H5a1 1 0 00-1 1v2a1 1 0 001 1zm12 0h2a1 1 0 001-1V5a1 1 0 00-1-1h-2a1 1 0 00-1 1v2a1 1 0 001 1zM5 20h2a1 1 0 001-1v-2a1 1 0 00-1-1H5a1 1 0 00-1 1v2a1 1 0 001 1z" />
                    </svg>
                  </button>

                  <%!-- Username (future: allow editing) --%>
                  <button
                    phx-click="open_name_modal"
                    class="w-full flex items-center justify-between p-3 rounded-xl bg-white/5 hover:bg-white/10 border border-white/5 hover:border-white/10 transition-all group"
                  >
                    <div class="flex items-center gap-3">
                      <div class="w-8 h-8 rounded-lg bg-white/5 flex items-center justify-center">
                        <svg class="w-4 h-4 text-white/70" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
                        </svg>
                      </div>
                      <div class="text-left">
                        <div class="text-sm font-medium text-white">Username</div>
                        <div class="text-xs text-white/40">@{@current_user.username}</div>
                      </div>
                    </div>
                    <svg class="w-4 h-4 text-white/30 group-hover:text-white/50 transition-colors" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
                    </svg>
                  </button>
                </div>
              </div>

              <%!-- Network Section --%>
              <div>
                <h3 class="text-[10px] font-bold text-white/40 uppercase tracking-widest px-3 mb-2">Network</h3>
                <div class="space-y-1">
                  <%!-- People/Contacts --%>
                  <button
                    phx-click="open_contacts_sheet"
                    class="w-full flex items-center justify-between p-3 rounded-xl bg-white/5 hover:bg-white/10 border border-white/5 hover:border-white/10 transition-all group"
                  >
                    <div class="flex items-center gap-3">
                      <div class="w-8 h-8 rounded-lg bg-white/5 flex items-center justify-center">
                        <svg class="w-4 h-4 text-white/70" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z" />
                        </svg>
                      </div>
                      <div class="text-left">
                        <div class="text-sm font-medium text-white">People</div>
                        <div class="text-xs text-white/40">Friends & contacts</div>
                      </div>
                    </div>
                    <svg class="w-4 h-4 text-white/30 group-hover:text-white/50 transition-colors" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
                    </svg>
                  </button>

                  <%!-- Groups --%>
                  <button
                    phx-click="open_groups_sheet"
                    class="w-full flex items-center justify-between p-3 rounded-xl bg-white/5 hover:bg-white/10 border border-white/5 hover:border-white/10 transition-all group"
                  >
                    <div class="flex items-center gap-3">
                      <div class="w-8 h-8 rounded-lg bg-white/5 flex items-center justify-center">
                        <svg class="w-4 h-4 text-white/70" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z" />
                        </svg>
                      </div>
                      <div class="text-left">
                        <div class="text-sm font-medium text-white">Groups</div>
                        <div class="text-xs text-white/40">Your private groups</div>
                      </div>
                    </div>
                    <svg class="w-4 h-4 text-white/30 group-hover:text-white/50 transition-colors" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
                    </svg>
                  </button>

                  <%!-- Friends & Trust --%>
                  <button
                    phx-click="open_contacts_sheet"
                    class="w-full flex items-center justify-between p-3 rounded-xl bg-white/5 hover:bg-white/10 border border-white/5 hover:border-white/10 transition-all group"
                  >
                    <div class="flex items-center gap-3">
                      <div class="w-8 h-8 rounded-lg bg-white/5 flex items-center justify-center">
                        <svg class="w-4 h-4 text-white/70" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
                        </svg>
                      </div>
                      <div class="text-left">
                        <div class="text-sm font-medium text-white">Trust Circle</div>
                        <div class="text-xs text-white/40">Recovery & trust</div>
                      </div>
                    </div>
                    <svg class="w-4 h-4 text-white/30 group-hover:text-white/50 transition-colors" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
                    </svg>
                  </button>

                  <%!-- Network Chord Visualization --%>
                  <button
                    phx-click="open_chord_diagram"
                    class="w-full flex items-center justify-between p-3 rounded-xl bg-white/5 hover:bg-white/10 border border-white/5 hover:border-white/10 transition-all group"
                  >
                    <div class="flex items-center gap-3">
                      <div class="w-8 h-8 rounded-lg bg-gradient-to-br from-emerald-500/20 to-purple-500/20 flex items-center justify-center">
                        <svg class="w-4 h-4 text-white/70" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <circle cx="12" cy="12" r="9" stroke-width="1.5"/>
                          <path stroke-linecap="round" stroke-width="1.5" d="M12 3a9 9 0 014.243 16.97M12 3a9 9 0 00-4.243 16.97"/>
                          <circle cx="12" cy="12" r="3" fill="currentColor" opacity="0.3"/>
                        </svg>
                      </div>
                      <div class="text-left">
                        <div class="text-sm font-medium text-white">Network Chord</div>
                        <div class="text-xs text-white/40">Visualize connections</div>
                      </div>
                    </div>
                    <svg class="w-4 h-4 text-white/30 group-hover:text-white/50 transition-colors" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
                    </svg>
                  </button>
                </div>
              </div>


              <%!-- Preferences Section --%>
              <div>
                <h3 class="text-[10px] font-bold text-white/40 uppercase tracking-widest px-3 mb-2">Preferences</h3>
                <div class="space-y-1">
                  <%!-- Color (Avatar Color) --%>
                  <div class="flex items-center justify-between p-3 rounded-xl bg-white/5 border border-white/5">
                    <div class="flex items-center gap-3">
                      <div class="w-8 h-8 rounded-lg bg-white/5 flex items-center justify-center">
                        <svg class="w-4 h-4 text-white/70" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 21a4 4 0 01-4-4V5a2 2 0 012-2h4a2 2 0 012 2v12a4 4 0 01-4 4zm0 0h12a2 2 0 002-2v-4a2 2 0 00-2-2h-2.343M11 7.343l1.657-1.657a2 2 0 012.828 0l2.829 2.829a2 2 0 010 2.828l-8.486 8.485M7 17h.01" />
                        </svg>
                      </div>
                      <div class="text-left">
                        <div class="text-sm font-medium text-white">Avatar Color</div>
                        <div class="text-xs text-white/40">Your personal color</div>
                      </div>
                    </div>
                    <div
                      class="w-8 h-8 rounded-lg border-2 border-white/20"
                      style={"background-color: #{friend_color(@current_user)}"}
                    ></div>
                  </div>
                </div>
              </div>

              <%!-- About Section --%>
              <div>
                <h3 class="text-[10px] font-bold text-white/40 uppercase tracking-widest px-3 mb-2">About</h3>
                <div class="space-y-1">
                  <%!-- Version --%>
                  <div class="flex items-center justify-between p-3 rounded-xl bg-white/5 border border-white/5">
                    <div class="flex items-center gap-3">
                      <div class="w-8 h-8 rounded-lg bg-white/5 flex items-center justify-center">
                        <svg class="w-4 h-4 text-white/70" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                        </svg>
                      </div>
                      <div class="text-left">
                        <div class="text-sm font-medium text-white">Version</div>
                        <div class="text-xs text-white/40">New Internet v0.1</div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <%!-- Footer - Sign Out --%>
            <div class="px-4 py-4 border-t border-white/5 bg-black/40 backdrop-blur-md">
              <button
                phx-click="sign_out"
                class="w-full flex items-center justify-center gap-2 p-3 rounded-xl bg-red-500/10 hover:bg-red-500/20 border border-red-500/20 hover:border-red-500/30 text-red-400 hover:text-red-300 transition-all font-medium"
              >
                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1" />
                </svg>
                <span>Sign Out</span>
              </button>
            </div>
          </div>
        </div>
      </div>
    <% end %>
    """
  end
end
