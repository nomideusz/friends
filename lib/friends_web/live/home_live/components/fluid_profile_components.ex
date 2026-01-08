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
  attr :trusted_friends, :list, default: []
  attr :trusted_friend_ids, :list, default: []
  attr :online_friend_ids, :any, default: nil
  attr :incoming_trust_requests, :list, default: []
  attr :outgoing_trust_requests, :list, default: []
  attr :avatar_position, :string, default: "top-right"

  def profile_sheet(assigns) do
    ~H"""
    <%= if @show do %>
      <div 
        id="profile-sheet" 
        class="fixed inset-0 z-[200]" 
        phx-window-keydown="close_profile_sheet" 
        phx-key="escape"
      >
        <%!-- Backdrop --%>
        <div 
          class="absolute inset-0 bg-black/80 backdrop-blur-sm animate-in fade-in duration-300"
          phx-click="close_profile_sheet"
        ></div>

        <%!-- Modal Content --%>
        <div class="absolute inset-0 bg-neutral-950 animate-in slide-in-from-bottom duration-300 flex flex-col sm:inset-4 sm:rounded-2xl sm:overflow-hidden sm:border sm:border-white/10 sm:max-w-2xl sm:mx-auto sm:shadow-2xl">
          
          <%!-- Header --%>
          <div class="p-6 border-b border-white/10 flex items-center justify-between bg-black/20 shrink-0">
             <div class="flex items-center gap-4">
                 <h2 class="text-2xl font-bold text-white tracking-tight">Devices & Settings</h2>
             </div>
             <button 
               phx-click="close_profile_sheet"
               class="w-8 h-8 flex items-center justify-center rounded-full bg-white/10 hover:bg-white/20 text-white/70 hover:text-white transition-colors cursor-pointer"
             >
               <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" /></svg>
             </button>
          </div>

          <%!-- Content --%>
          <div class="flex-1 overflow-y-auto p-4 scrollbar-hide">
            
            <%!-- Profile Info (Avatar + Name) --%>
             <div class="flex items-center gap-4 mb-8 px-2">
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

            <div class="space-y-6">
               <%!-- Account Section --%>
               <div>
                 <h3 class="text-[10px] font-bold text-white/40 uppercase tracking-widest px-3 mb-2">Account</h3>
                 <div class="space-y-1">
                   <%!-- Devices - Inline Display --%>
                   <div class="rounded-xl bg-white/5 border border-white/5 overflow-hidden">
                     <div class="flex items-center justify-between p-3">
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
                     </div>
                     
                     <%!-- Inline Devices List --%>
                     <div class="border-t border-white/5 px-3 py-2 space-y-2 bg-black/20">
                       <%= if @devices == [] do %>
                         <p class="text-xs text-white/30 text-center py-2">No devices found</p>
                       <% else %>
                         <%= for device <- @devices do %>
                           <div class="flex items-center justify-between p-2 rounded-lg bg-white/5">
                             <div class="flex items-center gap-2 min-w-0">
                               <div class="w-6 h-6 rounded bg-white/5 flex items-center justify-center flex-shrink-0">
                                 <svg class="w-3 h-3 text-white/50" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                   <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M12 18h.01M8 21h8a2 2 0 002-2V5a2 2 0 00-2-2H8a2 2 0 00-2 2v14a2 2 0 002 2z" />
                                 </svg>
                               </div>
                               <div class="min-w-0">
                                 <p class="text-xs text-white truncate">{device.device_name || "Unknown"}</p>
                                 <p class="text-[10px] text-white/30 font-mono">{String.slice(device.device_fingerprint || "", 0, 8)}...</p>
                               </div>
                             </div>
                             <button
                               phx-click="revoke_device"
                               phx-value-id={device.id}
                               data-confirm="Revoke this device?"
                               class="text-[10px] text-red-400/70 hover:text-red-400 px-2 cursor-pointer"
                             >
                               Revoke
                             </button>
                           </div>
                         <% end %>
                       <% end %>
                       
                       <%!-- Add Device Button --%>
                       <button
                         phx-click="create_pairing_token"
                         class="w-full flex items-center justify-center gap-2 p-2 rounded-lg bg-blue-500/10 hover:bg-blue-500/20 border border-blue-500/20 text-blue-400 text-xs font-medium transition-colors cursor-pointer"
                       >
                         <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                           <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
                         </svg>
                         Add Device
                       </button>
                     </div>
                   </div>
                 </div>
               </div>

               <%!-- Recovery Contacts Section --%>
               <div>
                 <% trusted_count = length(@trusted_friend_ids || []) %>
                 <div class="flex items-center justify-between px-3 mb-2">
                   <h3 class="text-[10px] font-bold text-white/40 uppercase tracking-widest">Recovery Contacts</h3>
                   <.recovery_strength count={trusted_count} />
                 </div>

                 <%!-- Pending Trust/Recovery Requests (incoming) --%>
                 <% incoming = assigns[:incoming_trust_requests] || [] %>
                 <%= if Enum.any?(incoming) do %>
                   <div class="mb-3">
                     <div class="text-[10px] font-medium text-yellow-400/70 uppercase tracking-wider mb-2 px-3">Recovery Requests</div>
                     <div class="space-y-1">
                       <%= for tf <- incoming do %>
                         <% user = if Map.has_key?(tf, :user), do: tf.user, else: tf %>
                         <.trust_request_row user={user} />
                       <% end %>
                     </div>
                   </div>
                 <% end %>

                 <%!-- Pending Recovery Invites (outgoing trust requests you sent) --%>
                 <% outgoing_trust = assigns[:outgoing_trust_requests] || [] %>
                 <%= if Enum.any?(outgoing_trust) do %>
                   <div class="mb-3">
                     <div class="text-[10px] font-medium text-purple-400/70 uppercase tracking-wider mb-2 px-3">Pending Recovery Invites</div>
                     <div class="space-y-1">
                       <%= for tr <- outgoing_trust do %>
                         <% user = if Map.has_key?(tr, :trusted_user), do: tr.trusted_user, else: tr %>
                         <.pending_recovery_invite_row user={user} />
                       <% end %>
                     </div>
                   </div>
                 <% end %>

                 <%= if trusted_count > 0 do %>
                   <div class="space-y-1">
                     <%= for tf <- @trusted_friends || [] do %>
                       <% user = if Map.has_key?(tf, :trusted_user), do: tf.trusted_user, else: tf %>
                       <.recovery_contact_row
                         user={user}
                         online={@online_friend_ids && MapSet.member?(@online_friend_ids, user.id)}
                       />
                     <% end %>
                   </div>
                 <% else %>
                   <%= if Enum.empty?(incoming) && Enum.empty?(outgoing_trust) do %>
                     <div class="text-center py-6">
                       <div class="w-12 h-12 mx-auto mb-3 rounded-full bg-green-500/10 flex items-center justify-center">
                         <svg class="w-6 h-6 text-green-400/50" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                           <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
                         </svg>
                       </div>
                       <p class="text-white/30 text-xs mb-3">No recovery contacts yet</p>
                       <button
                         phx-click="open_contacts_sheet"
                         class="px-3 py-1.5 rounded-lg bg-green-500/10 hover:bg-green-500/20 border border-green-500/20 hover:border-green-500/30 text-xs text-green-400 font-medium transition-colors inline-block cursor-pointer"
                       >
                         Add Recovery Contacts
                       </button>
                     </div>
                   <% end %>
                 <% end %>
               </div>

               <%!-- Network Section --%>
               <div>
                 <h3 class="text-[10px] font-bold text-white/40 uppercase tracking-widest px-3 mb-2">Network Visualization</h3>
                 <div class="space-y-1">
                   <%!-- Friends Graph --%>
                   <button
                     phx-click="show_my_constellation"
                     class="w-full flex items-center justify-between p-3 rounded-xl bg-white/5 hover:bg-white/10 border border-white/5 hover:border-white/10 transition-all group cursor-pointer"
                   >
                     <div class="flex items-center gap-3">
                       <div class="w-8 h-8 rounded-lg bg-gradient-to-br from-blue-500/20 to-cyan-500/20 flex items-center justify-center">
                         <svg class="w-4 h-4 text-white/70" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                           <circle cx="12" cy="5" r="2" stroke-width="1.5" />
                           <circle cx="6" cy="17" r="2" stroke-width="1.5" />
                           <circle cx="18" cy="17" r="2" stroke-width="1.5" />
                           <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M12 7v5M8.5 15.5L11 12M15.5 15.5L13 12" />
                         </svg>
                       </div>
                       <div class="text-left">
                         <div class="text-sm font-medium text-white">Friends Graph</div>
                         <div class="text-xs text-white/40">Your network visualization</div>
                       </div>
                     </div>
                     <svg class="w-4 h-4 text-white/30 group-hover:text-white/50 transition-colors" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                       <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
                     </svg>
                   </button>

                   <%!-- Network Chord Visualization --%>
                   <button
                     phx-click="open_chord_diagram"
                     class="w-full flex items-center justify-between p-3 rounded-xl bg-white/5 hover:bg-white/10 border border-white/5 hover:border-white/10 transition-all group cursor-pointer"
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

                   <%!-- Privacy Policy --%>
                   <a
                     href="/privacy"
                     target="_blank"
                     class="flex items-center justify-between p-3 rounded-xl bg-white/5 hover:bg-white/10 border border-white/5 hover:border-white/10 transition-all group"
                   >
                     <div class="flex items-center gap-3">
                       <div class="w-8 h-8 rounded-lg bg-white/5 flex items-center justify-center">
                         <svg class="w-4 h-4 text-white/70" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                           <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                         </svg>
                       </div>
                       <div class="text-left">
                         <div class="text-sm font-medium text-white">Privacy Policy</div>
                         <div class="text-xs text-white/40">How we handle your data</div>
                       </div>
                     </div>
                     <svg class="w-4 h-4 text-white/30 group-hover:text-white/50 transition-colors" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                       <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" />
                     </svg>
                   </a>

                   <%!-- Terms of Service --%>
                   <a
                     href="/privacy#terms"
                     target="_blank"
                     class="flex items-center justify-between p-3 rounded-xl bg-white/5 hover:bg-white/10 border border-white/5 hover:border-white/10 transition-all group"
                   >
                     <div class="flex items-center gap-3">
                       <div class="w-8 h-8 rounded-lg bg-white/5 flex items-center justify-center">
                         <svg class="w-4 h-4 text-white/70" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                           <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 6l3 1m0 0l-3 9a5.002 5.002 0 006.001 0M6 7l3 9M6 7l6-2m6 2l3-1m-3 1l-3 9a5.002 5.002 0 006.001 0M18 7l3 9m-3-9l-6-2m0-2v2m0 16V5m0 16H9m3 0h3" />
                         </svg>
                       </div>
                       <div class="text-left">
                         <div class="text-sm font-medium text-white">Terms of Service</div>
                         <div class="text-xs text-white/40">Usage rules & EULA</div>
                       </div>
                     </div>
                     <svg class="w-4 h-4 text-white/30 group-hover:text-white/50 transition-colors" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                       <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" />
                     </svg>
                   </a>
                 </div>
               </div>

               <%!-- Sign Out --%>
               <div class="pt-4 border-t border-white/10">
                 <button
                   phx-click="request_sign_out"
                   data-confirm="Sign out of your account?"
                   class="w-full flex items-center justify-center gap-2 p-3 rounded-xl bg-red-500/10 hover:bg-red-500/20 border border-red-500/20 hover:border-red-500/30 text-red-400 hover:text-red-300 transition-all font-medium cursor-pointer"
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
      </div>
    <% end %>
    """
  end



  # ============================================================================
  # RECOVERY STRENGTH INDICATOR
  # Shows how protected the account is
  # ============================================================================

  attr :count, :integer, default: 0

  def recovery_strength(assigns) do
    ~H"""
    <div class="flex items-center gap-1.5">
      <div class="flex gap-0.5">
        <%= for i <- 1..4 do %>
          <div class={"w-1.5 h-3 rounded-sm #{if i <= @count, do: "bg-green-400", else: "bg-white/10"}"}></div>
        <% end %>
      </div>
      <span class={"text-[10px] #{if @count >= 4, do: "text-green-400", else: "text-white/40"}"}>
        <%= if @count >= 4 do %>
          Protected
        <% else %>
          {@count}/4
        <% end %>
      </span>
    </div>
    """
  end

  # ============================================================================
  # RECOVERY CONTACT ROW
  # For the recovery contacts list - clickable to open 1-1 chat
  # ============================================================================

  attr :user, :map, required: true
  attr :online, :boolean, default: false

  def recovery_contact_row(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="open_dm"
      phx-value-user_id={@user.id}
      class="w-full flex items-center gap-3 py-2 px-3 rounded-xl bg-green-500/10 border border-green-500/20 hover:bg-green-500/15 transition-colors cursor-pointer"
    >
      <%!-- Avatar --%>
      <div
        class={"w-10 h-10 rounded-full flex items-center justify-center text-sm font-bold #{if @online, do: "avatar-online", else: ""}"}
        style={"background-color: #{friend_color(@user)};"}
      >
        <span class="text-white">{String.first(@user.username) |> String.upcase()}</span>
      </div>

      <%!-- Name with shield --%>
      <div class="flex-1 min-w-0 text-left">
        <div class="flex items-center gap-2">
          <span class="text-sm text-white truncate">@{@user.username}</span>
          <%= if @online do %>
            <span class="text-[10px] text-green-400/70">Here now</span>
          <% end %>
          <svg class="w-3.5 h-3.5 text-green-400 shrink-0" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M10 1.944A11.954 11.954 0 012.166 5C2.056 5.649 2 6.319 2 7c0 5.225 3.34 9.67 8 11.317C14.66 16.67 18 12.225 18 7c0-.682-.057-1.35-.166-2A11.954 11.954 0 0110 1.944zM11 14a1 1 0 11-2 0 1 1 0 012 0zm0-7a1 1 0 10-2 0v3a1 1 0 102 0V7z" clip-rule="evenodd" />
          </svg>
        </div>
      </div>

      <%!-- Remove button with confirmation --%>
      <button
        type="button"
        phx-click="remove_trusted_friend"
        phx-value-user_id={@user.id}
        data-confirm="Remove this person from your recovery contacts?"
        class="text-xs text-white/30 hover:text-red-400 transition-colors cursor-pointer px-2 shrink-0"
        onclick="event.stopPropagation();"
      >
        Remove
      </button>
    </button>
    """
  end

  # ============================================================================
  # TRUST REQUEST ROW
  # For incoming recovery contact requests (pending acceptance)
  # ============================================================================

  attr :user, :map, required: true

  def trust_request_row(assigns) do
    ~H"""
    <div class="flex items-center gap-3 py-2 px-3 rounded-xl bg-yellow-500/10 border border-yellow-500/20">
      <%!-- Avatar --%>
      <div
        class="w-10 h-10 rounded-full flex items-center justify-center text-sm font-bold"
        style={"background-color: #{friend_color(@user)};"}
      >
        <span class="text-white">{String.first(@user.username) |> String.upcase()}</span>
      </div>

      <%!-- Name --%>
      <div class="flex-1 min-w-0">
        <div class="flex items-center gap-2">
          <span class="text-sm text-white truncate">@{@user.username}</span>
          <span class="text-[10px] text-yellow-400/70">wants you as recovery</span>
        </div>
      </div>

      <%!-- Accept/Decline --%>
      <div class="flex items-center gap-2">
        <button
          phx-click="confirm_trusted_friend"
          phx-value-user_id={@user.id}
          class="text-xs text-green-400 hover:text-green-300 font-medium transition-colors cursor-pointer"
        >
          Accept
        </button>
        <button
          phx-click="decline_trusted_friend"
          phx-value-user_id={@user.id}
          class="text-xs text-white/40 hover:text-red-400 transition-colors cursor-pointer"
        >
          Decline
        </button>
      </div>
    </div>
    """
  end

  # ============================================================================
  # PENDING RECOVERY INVITE ROW
  # For outgoing trust requests (waiting for them to accept your recovery invite)
  # ============================================================================

  attr :user, :map, required: true

  def pending_recovery_invite_row(assigns) do
    ~H"""
    <div class="flex items-center gap-3 py-2 px-3 rounded-xl bg-purple-500/10 border border-purple-500/20">
      <%!-- Avatar --%>
      <div
        class="w-10 h-10 rounded-full flex items-center justify-center text-sm font-bold"
        style={"background-color: #{friend_color(@user)};"}
      >
        <span class="text-white">{String.first(@user.username) |> String.upcase()}</span>
      </div>

      <%!-- Name --%>
      <div class="flex-1 min-w-0">
        <div class="flex items-center gap-2">
          <span class="text-sm text-white truncate">@{@user.username}</span>
          <span class="text-[10px] text-purple-400/70">awaiting response</span>
        </div>
      </div>

      <%!-- Cancel button --%>
      <button
        phx-click="cancel_trust_request"
        phx-value-user_id={@user.id}
        class="text-xs text-white/40 hover:text-red-400 transition-colors cursor-pointer px-2"
      >
        Cancel
      </button>
    </div>
    """
  end


end
