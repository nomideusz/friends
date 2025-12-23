defmodule FriendsWeb.HomeLive.Components.FluidContactComponents do
  @moduledoc """
  Fluid design contact/people components.
  Simple bottom sheet for managing connections.
  """
  use FriendsWeb, :html
  import FriendsWeb.HomeLive.Helpers

  # ============================================================================
  # PEOPLE SHEET
  # Simple bottom sheet matching New Group modal style
  # ============================================================================

  attr :show, :boolean, default: false
  attr :mode, :atom, default: :add_contact
  attr :search_query, :string, default: ""
  attr :search_results, :list, default: []
  attr :current_user, :map, required: true
  attr :online_friend_ids, :any, default: nil
  attr :contacts, :list, default: []
  attr :outgoing_requests, :list, default: []  # Pending sent requests
  attr :incoming_requests, :list, default: []  # Requests from others to accept
  attr :trusted_friend_ids, :list, default: []
  attr :trusted_friends, :list, default: []
  attr :incoming_trust_requests, :list, default: []
  attr :outgoing_trust_requests, :list, default: []
  attr :pending_friend_requests, :list, default: []  # Actual friend requests to accept/decline
  attr :room, :map, default: nil
  attr :room_members, :list, default: []

  def contact_search_sheet(assigns) do
    mode = assigns[:mode] || :add_contact
    trusted_ids = assigns[:trusted_friend_ids] || []

    # Check if current user is admin
    is_admin = Friends.Social.is_admin?(assigns.current_user)

    assigns = assigns
      |> assign(:mode, mode)
      |> assign(:trusted_ids, trusted_ids)
      |> assign(:is_admin, is_admin)
      
    # Pre-calculate room member IDs for invite mode
    member_ids = if mode == :invite and assigns[:room_members] do
      Enum.map(assigns.room_members, & &1.user.id) |> MapSet.new()
    else
      MapSet.new()
    end
    
    assigns = assign(assigns, :member_ids, member_ids)

    ~H"""
    <%= if @show do %>
      <div id="people-sheet" class="fixed inset-0 z-[201]" phx-hook="LockScroll">
        <%!-- Backdrop --%>
        <div
          class="absolute inset-0 bg-black/70 backdrop-blur-sm animate-in fade-in duration-200"
          phx-click="close_contact_search"
        ></div>

        <%!-- Modal --%>
        <div class="absolute inset-x-0 bottom-0 z-10 flex justify-center animate-in slide-in-from-bottom duration-300 pointer-events-none">
          <div
            id="people-sheet-content"
            class="w-full max-w-lg bg-neutral-900/95 backdrop-blur-xl border-t border-x border-white/10 rounded-t-3xl shadow-2xl max-h-[80vh] flex flex-col pointer-events-auto"
            phx-click-away="close_contact_search"
            phx-hook="SwipeableDrawer"
            data-close-event="close_contact_search"
          >
            <%!-- Handle --%>
            <div class="py-3 flex justify-center cursor-pointer" phx-click="close_contact_search">
              <div class="w-10 h-1 rounded-full bg-white/20"></div>
            </div>

            <%!-- Search --%>
            <div class="px-4 pb-3">
              <input
                type="text"
                name="contact_search"
                value={@search_query}
                placeholder="Search by username..."
                phx-keyup="contact_search"
                phx-debounce="200"
                autocomplete="off"
                autofocus={@mode == :add_contact}
                class="w-full bg-white/5 border border-white/10 rounded-xl px-4 py-3 text-white placeholder-white/30 focus:border-white/30 focus:outline-none"
              />
            </div>

            <%!-- Results / People List --%>
            <div class="flex-1 overflow-y-auto px-4 pb-8">
              <% contacts = @contacts || [] %>
              <% outgoing = @outgoing_requests || [] %>
              <% outgoing_ids = Enum.map(outgoing, & &1.friend_user_id) %>
              <% trusted_count = length(@trusted_friend_ids || []) %>

              <%= if @search_query != "" do %>
                <%!-- Search Results --%>
                <%= if @search_results == [] do %>
                  <p class="text-center py-8 text-white/30 text-sm">No results</p>
                <% else %>
                  <div class="space-y-2">
                    <%= for user <- @search_results do %>
                      <% 
                        is_self = user.id == @current_user.id
                        is_contact = Enum.any?(contacts, fn c -> 
                          u = if Map.has_key?(c, :user), do: c.user, else: c
                          u.id == user.id 
                        end)
                        is_pending = user.id in outgoing_ids
                      %>
                      <.person_row 
                        user={user} 
                        status={cond do
                          is_self -> :self
                          is_contact -> :connected
                          is_pending -> :pending
                          true -> :add
                        end}
                        online={@online_friend_ids && MapSet.member?(@online_friend_ids, user.id)}
                        is_recovery={user.id in @trusted_ids}
                        mode={@mode}
                        member_ids={@member_ids}
                        is_admin={@is_admin}
                      />
                    <% end %>
                  </div>
                <% end %>
              <% else %>
                <%!-- Pending Friend Requests --%>
                <% friend_requests = @pending_friend_requests || [] %>
                <%= if Enum.any?(friend_requests) do %>
                  <div class="mb-4">
                    <div class="flex items-center gap-2 mb-2">
                      <svg class="w-3.5 h-3.5 text-blue-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M18 9v3m0 0v3m0-3h3m-3 0h-3m-2-5a4 4 0 11-8 0 4 4 0 018 0zM3 20a6 6 0 0112 0v1H3v-1z" />
                      </svg>
                      <span class="text-[10px] font-semibold text-blue-400 uppercase tracking-wider">Connection Requests</span>
                    </div>
                    <div class="space-y-1">
                      <%= for fr <- friend_requests do %>
                        <% user = if Map.has_key?(fr, :user), do: fr.user, else: fr %>
                        <.friend_request_row user={user} />
                      <% end %>
                    </div>
                  </div>
                <% end %>
                
                <%!-- Pending Connections (outgoing friend requests) --%>
                <%= if Enum.any?(outgoing) do %>
                  <div class="mb-4">
                    <div class="flex items-center gap-2 mb-2">
                      <svg class="w-3.5 h-3.5 text-white/50" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                      </svg>
                      <span class="text-[10px] font-medium text-white/40 uppercase tracking-wider">Pending Connections</span>
                    </div>
                    <div class="space-y-1">
                      <%= for req <- outgoing do %>
                        <% user = if Map.has_key?(req, :friend_user), do: req.friend_user, else: req %>
                        <.pending_connection_row user={user} />
                      <% end %>
                    </div>
                  </div>
                <% end %>
                
                <%!-- Pending Trust/Recovery Requests (incoming) --%>
                <% incoming = @incoming_requests || [] %>
                <%= if Enum.any?(incoming) do %>
                  <div class="mb-4">
                    <div class="text-[10px] font-medium text-yellow-400/70 uppercase tracking-wider mb-2">Recovery Requests</div>
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
                  <div class="mb-4">
                    <div class="text-[10px] font-medium text-purple-400/70 uppercase tracking-wider mb-2">Pending Recovery Invites</div>
                    <div class="space-y-1">
                      <%= for tr <- outgoing_trust do %>
                        <% user = if Map.has_key?(tr, :trusted_user), do: tr.trusted_user, else: tr %>
                        <.pending_recovery_invite_row user={user} />
                      <% end %>
                    </div>
                  </div>
                <% end %>
                
                <%!-- Recovery Contacts Section --%>
                <div class="mb-4">
                  <div class="flex items-center justify-between mb-2">
                    <div class="flex items-center gap-2">
                      <svg class="w-3.5 h-3.5 text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
                      </svg>
                      <span class="text-[10px] font-medium text-white/40 uppercase tracking-wider">Recovery Contacts</span>
                    </div>
                    <.recovery_strength count={trusted_count} />
                  </div>
                  
                  <%= if trusted_count > 0 do %>
                    <div class="space-y-1 mb-3">
                      <%= for tf <- @trusted_friends || [] do %>
                        <% user = if Map.has_key?(tf, :trusted_user), do: tf.trusted_user, else: tf %>
                        <.recovery_contact_row 
                          user={user}
                          online={@online_friend_ids && MapSet.member?(@online_friend_ids, user.id)}
                        />
                      <% end %>
                    </div>
                  <% end %>
                </div>
                
                <%!-- Your People (excluding recovery contacts) --%>
                <% non_recovery_contacts = Enum.reject(contacts, fn c -> 
                  u = if Map.has_key?(c, :user), do: c.user, else: c
                  u.id in @trusted_ids
                end) %>
                <div class="flex items-center gap-2 mb-2">
                  <svg class="w-3.5 h-3.5 text-white/50" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z" />
                  </svg>
                  <span class="text-[10px] font-medium text-white/40 uppercase tracking-wider">Your People</span>
                </div>
                <%= if Enum.any?(non_recovery_contacts) do %>
                  <div class="space-y-2">
                    <%= for contact <- non_recovery_contacts do %>
                      <% user = if Map.has_key?(contact, :user), do: contact.user, else: contact %>
                      <.person_row 
                        user={user} 
                        status={:connected}
                        online={@online_friend_ids && MapSet.member?(@online_friend_ids, user.id)}
                        is_recovery={false}
                        mode={@mode}
                        member_ids={@member_ids}
                        is_admin={@is_admin}
                      />
                    <% end %>
                  </div>
                <% else %>
                  <div class="text-center py-8">
                    <div class="w-16 h-16 mx-auto mb-4 rounded-full bg-white/5 flex items-center justify-center">
                      <svg class="w-8 h-8 text-white/30" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
                      </svg>
                    </div>
                    <p class="text-white/30 text-sm">Search to find and add people</p>
                  </div>
                <% end %>
              <% end %>
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
    <div
      class="flex items-center gap-3 py-2 px-2 rounded-xl bg-green-500/10 border border-green-500/20 hover:bg-green-500/15 transition-colors cursor-pointer"
      phx-click="open_dm"
      phx-value-user_id={@user.id}
    >
      <%!-- Avatar --%>
      <div
        class={"w-10 h-10 rounded-full flex items-center justify-center text-sm font-bold #{if @online, do: "avatar-online", else: ""}"}
        style={"background-color: #{friend_color(@user)};"}
      >
        <span class="text-white">{String.first(@user.username) |> String.upcase()}</span>
      </div>

      <%!-- Name with shield --%>
      <div class="flex-1 min-w-0">
        <div class="flex items-center gap-2">
          <span class="text-sm text-white truncate">@{@user.username}</span>
          <%= if @online do %>
            <span class="text-[10px] text-green-400/70">Here now</span>
          <% end %>
          <.shield_icon class="w-3.5 h-3.5 text-green-400" />
        </div>
      </div>

      <%!-- Remove button with confirmation --%>
      <button
        phx-click="remove_trusted_friend"
        phx-value-user_id={@user.id}
        data-confirm="Remove this person from your recovery contacts?"
        class="text-xs text-white/30 hover:text-red-400 transition-colors cursor-pointer px-2"
      >
        Remove
      </button>
    </div>
    """
  end

  # ============================================================================
  # PENDING CONNECTION ROW
  # For outgoing friend requests (waiting for them to accept)
  # ============================================================================

  attr :user, :map, required: true

  def pending_connection_row(assigns) do
    ~H"""
    <div class="flex items-center gap-3 py-2 px-2 rounded-xl bg-white/5 border border-white/10">
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
          <span class="text-[10px] text-white/40">pending</span>
        </div>
      </div>

      <%!-- Cancel button --%>
      <button
        phx-click="cancel_request"
        phx-value-user_id={@user.id}
        class="text-xs text-white/40 hover:text-red-400 transition-colors cursor-pointer px-2"
      >
        Cancel
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
    <div class="flex items-center gap-3 py-2 px-2 rounded-xl bg-yellow-500/10 border border-yellow-500/20">
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
    <div class="flex items-center gap-3 py-2 px-2 rounded-xl bg-purple-500/10 border border-purple-500/20">
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

  # ============================================================================
  # FRIEND REQUEST ROW
  # For incoming friend requests (pending acceptance)
  # ============================================================================

  attr :user, :map, required: true

  def friend_request_row(assigns) do
    ~H"""
    <div class="flex items-center gap-3 py-2 px-2 rounded-xl bg-blue-500/10 border border-blue-500/20">
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
          <span class="text-[10px] text-blue-400/70">wants to connect</span>
        </div>
      </div>

      <%!-- Accept/Decline --%>
      <div class="flex items-center gap-2">
        <button
          phx-click="accept_friend_request"
          phx-value-user_id={@user.id}
          class="text-xs text-green-400 hover:text-green-300 font-medium transition-colors cursor-pointer"
        >
          Accept
        </button>
        <button
          phx-click="decline_friend_request"
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
  # SVG ICONS
  # ============================================================================

  attr :class, :string, default: "w-4 h-4"

  def shield_icon(assigns) do
    ~H"""
    <svg class={@class} fill="currentColor" viewBox="0 0 20 20">
      <path fill-rule="evenodd" d="M10 1.944A11.954 11.954 0 012.166 5C2.056 5.649 2 6.319 2 7c0 5.225 3.34 9.67 8 11.317C14.66 16.67 18 12.225 18 7c0-.682-.057-1.35-.166-2A11.954 11.954 0 0110 1.944zM11 14a1 1 0 11-2 0 1 1 0 012 0zm0-7a1 1 0 10-2 0v3a1 1 0 102 0V7z" clip-rule="evenodd" />
    </svg>
    """
  end

  # ============================================================================
  # PERSON ROW
  # Shows person with appropriate action based on status
  # ============================================================================

  attr :user, :map, required: true
  attr :status, :atom, default: :add  # :add, :pending, :connected, :self
  attr :online, :boolean, default: false
  attr :is_recovery, :boolean, default: false
  attr :mode, :atom, default: :add_contact
  attr :member_ids, :any, default: %MapSet{}
  attr :is_admin, :boolean, default: false

  def person_row(assigns) do

    ~H"""
    <div class="flex items-center gap-3 py-2">
      <%!-- Avatar --%>
      <div
        class={"w-10 h-10 rounded-full flex items-center justify-center text-sm font-bold #{if @online, do: "avatar-online", else: ""}"}
        style={"background-color: #{friend_color(@user)};"}
      >
        <span class="text-white">{String.first(@user.username) |> String.upcase()}</span>
      </div>

      <%!-- Name --%>
      <div class="flex-1 min-w-0">
        <div class="flex items-center gap-2">
          <span class="text-sm text-white truncate">@{@user.username}</span>
          <%= if @online do %>
            <span class="text-[10px] text-green-400/70">Here now</span>
          <% end %>
          <%= if @is_recovery && @status == :connected do %>
            <.shield_icon class="w-3.5 h-3.5 text-green-400" />
          <% end %>
        </div>
      </div>

      <%!-- Actions --%>
      <div class="flex items-center gap-2">
          <%= case @status do %>
            <% :self -> %>
              <span class="text-xs text-white/30">You</span>
            <% :connected -> %>
              <%!-- Recovery promote/demote --%>
              <%= if @is_recovery do %>
                <button
                  phx-click="remove_trusted_friend"
                  phx-value-user_id={@user.id}
                  data-confirm="Remove from recovery contacts?"
                  class="p-1.5 rounded-lg text-green-400 hover:bg-green-400/10 transition-colors cursor-pointer"
                  title="Remove from Recovery"
                >
                  <.shield_icon class="w-4 h-4" />
                </button>
              <% else %>
                <button
                  phx-click="add_trusted_friend"
                  phx-value-user_id={@user.id}
                  class="p-1.5 rounded-lg text-white/30 hover:text-green-400 hover:bg-green-400/10 transition-colors cursor-pointer"
                  title="Add to Recovery"
                >
                  <.shield_icon class="w-4 h-4" />
                </button>
              <% end %>
              <%!-- Remove friend --%>
              <button
                phx-click="remove_contact"
                phx-value-user_id={@user.id}
                class="text-xs text-red-400/60 hover:text-red-400 transition-colors cursor-pointer"
              >
                Remove
              </button>
            <% :pending -> %>
              <button
                phx-click="cancel_request"
                phx-value-user_id={@user.id}
                class="text-xs text-white/40 hover:text-white transition-colors cursor-pointer"
              >
                Cancel
              </button>
            <% :add -> %>
              <button
                phx-click="send_friend_request"
                phx-value-user_id={@user.id}
                class="text-xs text-blue-400 hover:text-blue-300 font-medium transition-colors cursor-pointer"
              >
                Add
              </button>
          <% end %>
          <%!-- Admin delete user button --%>
          <%= if @is_admin && @status != :self do %>
            <button
              type="button"
              phx-click="admin_delete_user"
              phx-value-user_id={@user.id}
              data-confirm="DELETE user @#{@user.username} and ALL their content? This cannot be undone!"
              class="p-1.5 rounded-lg text-red-400/50 hover:text-red-400 hover:bg-red-400/10 transition-colors cursor-pointer"
              title="Delete user (admin)"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
              </svg>
            </button>
          <% end %>
      </div>
    </div>
    """
  end
end
