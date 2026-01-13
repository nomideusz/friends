defmodule FriendsWeb.HomeLive.Components.FluidProfileComponents do
  @moduledoc """
  Fluid design profile and settings components.
  Simple bottom sheet for user profile and settings.
  """
  use FriendsWeb, :html
  import FriendsWeb.HomeLive.Helpers
  import FriendsWeb.HomeLive.Components.FluidContactComponents, only: [avatar: 1]

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
  attr :active_tab, :string, default: "profile"

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
        <div class="absolute inset-x-0 bottom-0 top-12 sm:inset-12 md:inset-24 max-w-5xl mx-auto
                    bg-[#121212] rounded-t-2xl sm:rounded-2xl border border-white/10 shadow-2xl overflow-hidden flex flex-col
                    animate-in slide-in-from-bottom duration-300">
          
          <%!-- Header --%>
          <div class="p-6 border-b border-white/10 flex items-center justify-between bg-black/20 shrink-0">
             <div class="flex items-center gap-4">
                 <h2 class="text-2xl font-bold text-white tracking-tight">Settings</h2>
             </div>
             <button 
               phx-click="close_profile_sheet"
               class="w-8 h-8 flex items-center justify-center rounded-full bg-white/10 hover:bg-white/20 text-white/70 hover:text-white transition-colors cursor-pointer"
             >
               <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" /></svg>
             </button>
          </div>

          <%!-- Main Layout --%>
          <div class="flex-1 flex overflow-hidden">
            <%!-- Desktop Sidebar --%>
            <div class="hidden md:flex flex-col w-64 border-r border-white/10 bg-black/20 p-3 gap-1 shrink-0 overflow-y-auto">
               <.nav_item tab="profile" label="Profile" icon="profile" active={@active_tab} />
               <.nav_item tab="account" label="Account" icon="account" active={@active_tab} />
               <.nav_item tab="recovery" label="Recovery" icon="recovery" active={@active_tab} />
               <.nav_item tab="network" label="Network" icon="network" active={@active_tab} />
               <.nav_item tab="about" label="About" icon="about" active={@active_tab} />
            </div>

            <%!-- Content Area --%>
            <div class="flex-1 overflow-y-auto p-4 md:p-8 scrollbar-hide bg-[#121212]">
              
              <%!-- Mobile Stack (visible only on mobile) --%>
              <div class="md:hidden space-y-12 pb-12">
                <.profile_section current_user={@current_user} uploads={@uploads} />
                <.account_section devices={@devices} />
                <.recovery_section 
                   trusted_friends={@trusted_friends} 
                   trusted_friend_ids={@trusted_friend_ids}
                   incoming_trust_requests={@incoming_trust_requests}
                   outgoing_trust_requests={@outgoing_trust_requests}
                   online_friend_ids={@online_friend_ids}
                />
                <.network_section />
                <.about_section />
              </div>

              <%!-- Desktop Tab Content (visible only on desktop) --%>
              <div class="hidden md:block max-w-2xl">
                 <%= case @active_tab do %>
                    <% "profile" -> %>
                       <.profile_section current_user={@current_user} uploads={@uploads} />
                    <% "account" -> %>
                       <.account_section devices={@devices} />
                    <% "recovery" -> %>
                       <.recovery_section 
                          trusted_friends={@trusted_friends} 
                          trusted_friend_ids={@trusted_friend_ids}
                          incoming_trust_requests={@incoming_trust_requests}
                          outgoing_trust_requests={@outgoing_trust_requests}
                          online_friend_ids={@online_friend_ids}
                       />
                    <% "network" -> %>
                       <.network_section />
                    <% "about" -> %>
                       <.about_section />
                    <% _ -> %>
                       <.profile_section current_user={@current_user} uploads={@uploads} />
                 <% end %>
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
    <div class="flex items-center gap-3 py-2 px-3 rounded-xl bg-green-500/10 border border-green-500/20 hover:bg-green-500/15 transition-colors group">
      <%!-- Clickable Content Area --%>
      <button
        type="button"
        phx-click="open_dm"
        phx-value-user_id={@user.id}
        class="flex items-center gap-3 flex-1 min-w-0 text-left bg-transparent border-0 p-0 cursor-pointer"
      >
        <%!-- Avatar --%>
        <.avatar user={@user} online={@online} />

        <%!-- Name with shield --%>
        <div class="flex-1 min-w-0">
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
      </button>

      <%!-- Remove button with confirmation --%>
      <button
        type="button"
        phx-click="remove_trusted_friend"
        phx-value-user_id={@user.id}
        data-confirm="Remove this person from your recovery contacts?"
        class="text-xs text-white/30 hover:text-red-400 transition-colors cursor-pointer px-2 shrink-0"
      >
        Remove
      </button>
    </div>
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
      <.avatar user={@user} />

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
      <.avatar user={@user} />

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



  # ============================================================================
  # PRIVATE COMPONENTS
  # ============================================================================

  attr :tab, :string, required: true
  attr :label, :string, required: true
  attr :icon, :string, default: nil
  attr :active, :string, required: true
  
  defp nav_item(assigns) do
    ~H"""
    <button
      phx-click="switch_settings_tab"
      phx-value-tab={@tab}
      class={[
        "w-full flex items-center gap-3 px-3 py-2 rounded-lg text-sm font-medium transition-all group cursor-pointer",
        @active == @tab && "bg-white/10 text-white shadow-sm",
        @active != @tab && "text-white/60 hover:text-white hover:bg-white/5"
      ]}
    >
      <%= if @icon do %>
        <div class={[
          "w-6 h-6 rounded flex items-center justify-center transition-colors",
          @active == @tab && "text-white",
          @active != @tab && "text-white/50 group-hover:text-white/70"
        ]}>
          <.icon name={@icon} class="w-4 h-4" />
        </div>
      <% end %>
      <span>{@label}</span>
      
      <%= if @active == @tab do %>
        <div class="ml-auto w-1.5 h-1.5 rounded-full bg-blue-400"></div>
      <% end %>
    </button>
    """
  end
  
  # ... Content Sections ...
  
  attr :current_user, :map, required: true
  attr :uploads, :map, default: nil
  
  defp profile_section(assigns) do
    ~H"""
    <div class="space-y-8 animate-in fade-in slide-in-from-bottom-2 duration-300">
      <div class="flex items-center gap-4 px-2">
        <%!-- Avatar with Upload --%>
        <form phx-change="validate_avatar" phx-submit="upload_avatar" class="relative flex-shrink-0">
          <label class="relative block cursor-pointer group">
            <div
              class="w-20 h-20 rounded-full flex items-center justify-center text-3xl font-bold text-black border-2 border-white/10 shadow-lg overflow-hidden"
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
          <h2 class="text-2xl font-bold text-white truncate">@{@current_user.username}</h2>
          <p class="text-xs text-white/40 font-mono mt-1">ID: {@current_user.id}</p>
          <div class="mt-3 flex gap-2">
             <button phx-click="open_name_modal" class="text-xs bg-white/10 hover:bg-white/20 px-3 py-1.5 rounded-lg transition-colors cursor-pointer">
               Edit Name
             </button>
             <button 
               phx-click="request_sign_out" 
               data-confirm="Sign out?" 
               class="text-xs bg-red-500/10 hover:bg-red-500/20 text-red-400 border border-red-500/20 px-3 py-1.5 rounded-lg transition-colors cursor-pointer"
             >
               Sign Out
             </button>
          </div>
        </div>
      </div>
    </div>
    """
  end
  
  attr :devices, :list, default: []
  
  defp account_section(assigns) do
    ~H"""
    <div class="space-y-6 animate-in fade-in slide-in-from-bottom-2 duration-300">
      <div>
        <h3 class="text-lg font-bold text-white mb-1">Devices</h3>
        <p class="text-sm text-white/50 mb-4">Manage devices connected to your account.</p>
        
        <div class="space-y-3">
          <%= if @devices == [] do %>
            <div class="p-8 rounded-2xl bg-white/5 border border-white/5 text-center">
              <p class="text-white/30 text-sm">No other devices found</p>
            </div>
          <% else %>
             <div class="grid grid-cols-1 gap-3">
              <%= for device <- @devices do %>
                <div class="flex items-center justify-between p-4 rounded-xl bg-white/5 border border-white/5 hover:border-white/10 transition-colors">
                  <div class="flex items-center gap-4 min-w-0">
                    <div class="w-10 h-10 rounded-lg bg-black/40 flex items-center justify-center flex-shrink-0">
                      <svg class="w-5 h-5 text-white/50" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M12 18h.01M8 21h8a2 2 0 002-2V5a2 2 0 00-2-2H8a2 2 0 00-2 2v14a2 2 0 002 2z" />
                      </svg>
                    </div>
                    <div class="min-w-0">
                      <p class="text-sm font-medium text-white truncate">{device.device_name || "Unknown Device"}</p>
                      <p class="text-xs text-white/30 font-mono italic">{String.slice(device.device_fingerprint || "", 0, 12)}...</p>
                    </div>
                  </div>
                  <button
                    phx-click="revoke_device"
                    phx-value-id={device.id}
                    data-confirm="Revoke access for this device?"
                    class="text-xs text-red-400/70 hover:text-red-400 hover:bg-red-400/10 px-3 py-1.5 rounded-lg transition-colors cursor-pointer"
                  >
                    Revoke
                  </button>
                </div>
              <% end %>
             </div>
          <% end %>
          
          <button
            phx-click="create_pairing_token"
            class="w-full flex items-center justify-center gap-2 p-3 rounded-xl bg-blue-500/10 hover:bg-blue-500/20 border border-blue-500/20 text-blue-400 text-sm font-medium transition-colors cursor-pointer mt-4"
          >
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
            </svg>
            Link New Device
          </button>
        </div>
      </div>
    </div>
    """
  end
  
  attr :trusted_friends, :list, default: []
  attr :trusted_friend_ids, :list, default: []
  attr :incoming_trust_requests, :list, default: []
  attr :outgoing_trust_requests, :list, default: []
  attr :online_friend_ids, :any, default: nil
  
  defp recovery_section(assigns) do
    ~H"""
    <div class="space-y-6 animate-in fade-in slide-in-from-bottom-2 duration-300">
      <div>
        <div class="flex items-center justify-between mb-2">
           <div>
             <h3 class="text-lg font-bold text-white">Recovery Contacts</h3>
             <p class="text-sm text-white/50">Trusted friends who can help you recover your account.</p>
           </div>
           <% trusted_count = length(@trusted_friend_ids || []) %>
           <.recovery_strength count={trusted_count} />
        </div>
        
        <div class="space-y-6 mt-6">
           <%!-- Incoming --%>
           <% incoming = assigns[:incoming_trust_requests] || [] %>
           <%= if Enum.any?(incoming) do %>
             <div>
               <h4 class="text-xs font-bold text-yellow-500 uppercase tracking-widest mb-3">Requests for You</h4>
               <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
                 <%= for tf <- incoming do %>
                   <% user = if Map.has_key?(tf, :user), do: tf.user, else: tf %>
                   <.trust_request_row user={user} />
                 <% end %>
               </div>
             </div>
           <% end %>
           
           <%!-- Outgoing --%>
           <% outgoing_trust = assigns[:outgoing_trust_requests] || [] %>
           <%= if Enum.any?(outgoing_trust) do %>
             <div>
               <h4 class="text-xs font-bold text-purple-400 uppercase tracking-widest mb-3">Pending Invites</h4>
               <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
                 <%= for tr <- outgoing_trust do %>
                   <% user = if Map.has_key?(tr, :trusted_user), do: tr.trusted_user, else: tr %>
                   <.pending_recovery_invite_row user={user} />
                 <% end %>
               </div>
             </div>
           <% end %>
           
           <%!-- Trusted List --%>
           <div>
             <h4 class="text-xs font-bold text-green-400 uppercase tracking-widest mb-3">Trusted Contacts</h4>
             <%= if trusted_count > 0 do %>
               <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
                 <%= for tf <- @trusted_friends || [] do %>
                   <% user = if Map.has_key?(tf, :trusted_user), do: tf.trusted_user, else: tf %>
                   <.recovery_contact_row
                     user={user}
                     online={@online_friend_ids && MapSet.member?(@online_friend_ids, user.id)}
                   />
                 <% end %>
               </div>
             <% else %>
               <div class="p-6 rounded-xl bg-white/5 border border-white/5 text-center">
                 <p class="text-white/30 text-sm mb-4">You haven't added any recovery contacts yet.</p>
                 <button
                   phx-click="open_contacts_sheet"
                   class="px-4 py-2 rounded-lg bg-green-500/10 hover:bg-green-500/20 text-green-400 text-sm font-medium transition-colors cursor-pointer"
                 >
                   Select Contacts
                 </button>
               </div>
             <% end %>
           </div>
        </div>
      </div>
    </div>
    """
  end
  
  defp network_section(assigns) do
    ~H"""
    <div class="space-y-6 animate-in fade-in slide-in-from-bottom-2 duration-300">
       <div>
         <h3 class="text-lg font-bold text-white mb-1">Network Visualization</h3>
         <p class="text-sm text-white/50 mb-6">Explore your social graph and connections.</p>
         
         <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <%!-- Friends Graph --%>
           <button
             phx-click="show_my_constellation"
             class="flex flex-col items-center justify-center p-6 rounded-2xl bg-white/5 hover:bg-white/10 border border-white/5 hover:border-white/10 transition-all group cursor-pointer text-center"
           >
             <div class="w-16 h-16 rounded-2xl bg-gradient-to-br from-blue-500/20 to-cyan-500/20 flex items-center justify-center mb-4 group-hover:scale-110 transition-transform">
               <svg class="w-8 h-8 text-blue-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                 <circle cx="12" cy="5" r="2" stroke-width="1.5" />
                 <circle cx="6" cy="17" r="2" stroke-width="1.5" />
                 <circle cx="18" cy="17" r="2" stroke-width="1.5" />
                 <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M12 7v5M8.5 15.5L11 12M15.5 15.5L13 12" />
               </svg>
             </div>
             <div class="text-lg font-bold text-white mb-1">Friends Graph</div>
             <p class="text-xs text-white/40">Interactive 2D force-directed graph of your network</p>
           </button>

           <%!-- Network Chord Visualization --%>
           <button
             phx-click="open_chord_diagram"
             class="flex flex-col items-center justify-center p-6 rounded-2xl bg-white/5 hover:bg-white/10 border border-white/5 hover:border-white/10 transition-all group cursor-pointer text-center"
           >
             <div class="w-16 h-16 rounded-2xl bg-gradient-to-br from-emerald-500/20 to-purple-500/20 flex items-center justify-center mb-4 group-hover:scale-110 transition-transform">
               <svg class="w-8 h-8 text-emerald-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                 <circle cx="12" cy="12" r="9" stroke-width="1.5"/>
                 <path stroke-linecap="round" stroke-width="1.5" d="M12 3a9 9 0 014.243 16.97M12 3a9 9 0 00-4.243 16.97"/>
                 <circle cx="12" cy="12" r="3" fill="currentColor" opacity="0.3"/>
               </svg>
             </div>
             <div class="text-lg font-bold text-white mb-1">Network Chord</div>
             <p class="text-xs text-white/40">Circular chord diagram showing flow and density</p>
           </button>
         </div>
       </div>
    </div>
    """
  end
  
  defp about_section(assigns) do
    ~H"""
    <div class="space-y-6 animate-in fade-in slide-in-from-bottom-2 duration-300">
      <div>
        <h3 class="text-lg font-bold text-white mb-1">About New Internet</h3>
        <p class="text-sm text-white/50 mb-6">Version info and legal documents.</p>
        
        <div class="space-y-3">
          <div class="flex items-center justify-between p-4 rounded-xl bg-white/5 border border-white/5">
            <div class="flex items-center gap-4">
              <div class="w-10 h-10 rounded-lg bg-white/5 flex items-center justify-center">
                <svg class="w-5 h-5 text-white/70" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
              </div>
              <div>
                <div class="text-sm font-medium text-white">Version</div>
                <div class="text-xs text-white/40">New Internet v0.1 (Beta)</div>
              </div>
            </div>
          </div>
          
           <%!-- Privacy Policy --%>
           <a
             href="/privacy"
             target="_blank"
             class="flex items-center justify-between p-4 rounded-xl bg-white/5 hover:bg-white/10 border border-white/5 hover:border-white/10 transition-all group"
           >
             <div class="flex items-center gap-4">
               <div class="w-10 h-10 rounded-lg bg-white/5 flex items-center justify-center">
                 <svg class="w-5 h-5 text-white/70" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                   <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                 </svg>
               </div>
               <div>
                 <div class="text-sm font-medium text-white">Privacy Policy</div>
                 <div class="text-xs text-white/40">How we handle your data</div>
               </div>
             </div>
             <svg class="w-5 h-5 text-white/30 group-hover:text-white/50 transition-colors" fill="none" stroke="currentColor" viewBox="0 0 24 24">
               <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" />
             </svg>
           </a>

           <%!-- Terms of Service --%>
           <a
             href="/privacy#terms"
             target="_blank"
             class="flex items-center justify-between p-4 rounded-xl bg-white/5 hover:bg-white/10 border border-white/5 hover:border-white/10 transition-all group"
           >
             <div class="flex items-center gap-4">
               <div class="w-10 h-10 rounded-lg bg-white/5 flex items-center justify-center">
                 <svg class="w-5 h-5 text-white/70" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                   <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 6l3 1m0 0l-3 9a5.002 5.002 0 006.001 0M6 7l3 9M6 7l6-2m6 2l3-1m-3 1l-3 9a5.002 5.002 0 006.001 0M18 7l3 9m-3-9l-6-2m0-2v2m0 16V5m0 16H9m3 0h3" />
                 </svg>
               </div>
               <div>
                 <div class="text-sm font-medium text-white">Terms of Service</div>
                 <div class="text-xs text-white/40">Usage rules & EULA</div>
               </div>
             </div>
             <svg class="w-5 h-5 text-white/30 group-hover:text-white/50 transition-colors" fill="none" stroke="currentColor" viewBox="0 0 24 24">
               <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" />
             </svg>
           </a>
        </div>
      </div>
    </div>
    """
  end
  
  defp icon(assigns) do
    # Simple icon helper to keep template clean
     case assigns.name do
       "profile" ->
         ~H"""
         <svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" /></svg>
         """
       "account" ->
         ~H"""
         <svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 18h.01M8 21h8a2 2 0 002-2V5a2 2 0 00-2-2H8a2 2 0 00-2 2v14a2 2 0 002 2z" /></svg>
         """
       "recovery" ->
         ~H"""
         <svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" /></svg>
         """
       "network" ->
         ~H"""
         <svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1" /></svg>
         """
       "about" ->
         ~H"""
         <svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" /></svg>
         """
       _ ->
         ~H"""
         <svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 12h.01M12 12h.01M19 12h.01M6 12a1 1 0 11-2 0 1 1 0 012 0zm7 0a1 1 0 11-2 0 1 1 0 012 0zm7 0a1 1 0 11-2 0 1 1 0 012 0z" /></svg>
         """
     end
  end
end


