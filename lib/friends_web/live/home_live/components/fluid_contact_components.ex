defmodule FriendsWeb.HomeLive.Components.FluidContactComponents do
  @moduledoc """
  Fluid design contact/people components.
  Simple bottom sheet for managing connections.
  """
  use FriendsWeb, :html
  import FriendsWeb.HomeLive.Helpers

  # ============================================================================
  # PEOPLE MODAL
  # Full-screen modal for People (Contacts)
  # ============================================================================

  attr :show, :boolean, default: false
  attr :contact_mode, :string, default: "list"
  attr :contacts, :list, default: []
  attr :search_query, :string, default: ""
  attr :search_results, :list, default: []
  attr :trusted_friend_ids, :any, default: MapSet.new()
  attr :trusted_friends, :list, default: []
  attr :incoming_trust_requests, :list, default: []
  attr :outgoing_requests, :list, default: []
  attr :outgoing_trust_requests, :list, default: []
  attr :pending_friend_requests, :list, default: []
  attr :room, :any, default: nil
  attr :room_members, :list, default: []
  attr :current_user, :map, required: true
  attr :online_friend_ids, :any, default: MapSet.new()

  def fluid_people_modal(assigns) do
    ~H"""
    <%= if @show do %>
      <div 
        id="fluid-people-modal" 
        class="fixed inset-0 z-[200]"
        phx-window-keydown="close_people_modal"
        phx-key="escape"
      >
        <%!-- Backdrop --%>
        <div 
          class="absolute inset-0 bg-black/80 backdrop-blur-sm animate-in fade-in duration-300"
          phx-click="close_people_modal"
        ></div>

        <%!-- Modal Content --%>
        <div class="absolute inset-0 bg-neutral-950 animate-in slide-in-from-bottom duration-300 flex flex-col sm:inset-4 sm:rounded-2xl sm:overflow-hidden sm:border sm:border-white/10 sm:max-w-2xl md:max-w-4xl lg:max-w-5xl sm:mx-auto sm:shadow-2xl">
          <%!-- Header --%>
          <div class="p-6 border-b border-white/10 flex items-center justify-between bg-black/20 shrink-0">
            <h2 class="text-2xl font-bold text-white tracking-tight">People</h2>
            <button 
              phx-click="close_people_modal"
              class="w-8 h-8 flex items-center justify-center rounded-full bg-white/10 hover:bg-white/20 text-white/70 hover:text-white transition-colors cursor-pointer"
            >
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" /></svg>
            </button>
          </div>

          <%!-- Content --%>
          <div class="flex-1 overflow-y-auto p-4 scrollbar-hide">
            <.people_drawer_content
               mode={@contact_mode}
               contacts={@contacts}
               search_query={@search_query}
               search_results={@search_results}
               trusted_friend_ids={@trusted_friend_ids}
               trusted_friends={@trusted_friends}
               incoming_trust_requests={@incoming_trust_requests}
               outgoing_requests={@outgoing_requests}
               outgoing_trust_requests={@outgoing_trust_requests}
               pending_friend_requests={@pending_friend_requests}
               room={@room}
               room_members={@room_members}
               current_user={@current_user}
               online_friend_ids={@online_friend_ids}
            />
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  # ============================================================================
  # PEOPLE DRAWER CONTENT
  # Content-only component for use inside TetheredDrawer
  # ============================================================================

  attr :mode, :atom, default: :add_contact
  attr :search_query, :string, default: ""
  attr :search_results, :list, default: []
  attr :current_user, :map, required: true
  attr :online_friend_ids, :any, default: nil
  attr :contacts, :list, default: []
  attr :outgoing_requests, :list, default: []
  attr :pending_friend_requests, :list, default: []
  attr :trusted_friend_ids, :list, default: []
  attr :trusted_friends, :list, default: []
  attr :incoming_trust_requests, :list, default: []
  attr :outgoing_trust_requests, :list, default: []
  attr :room, :map, default: nil
  attr :room_members, :list, default: []

  def people_drawer_content(assigns) do
    is_admin = Friends.Social.is_admin?(assigns.current_user)
    trusted_ids = assigns[:trusted_friend_ids] || []
    
    member_ids = if assigns.room && assigns.room_members do
      Enum.map(assigns.room_members, fn m ->
        cond do
          is_map(m) && Map.has_key?(m, :user_id) -> m.user_id
          is_map(m) && Map.has_key?(m, :id) -> m.id
          true -> nil
        end
      end) |> Enum.reject(&is_nil/1)
    else
      []
    end
    
    assigns = assigns
      |> assign(:is_admin, is_admin)
      |> assign(:trusted_ids, trusted_ids)
      |> assign(:member_ids, member_ids)

    ~H"""
    <div class="flex flex-col h-full">
      <%!-- Search --%>
      <div class="px-4 py-3 border-b border-white/10">
        <input
          type="text"
          name="contact_search"
          value={@search_query}
          placeholder="Search by username..."
          phx-keyup="contact_search"
          phx-debounce="200"
          autocomplete="off"
          class="w-full bg-white/5 border border-white/10 rounded-lg px-3 py-2 text-sm text-white placeholder-white/30 focus:border-white/30 focus:outline-none"
        />
      </div>

      <%!-- Results / People List --%>
      <div class="flex-1 overflow-y-auto px-4 py-3">
        <% contacts = @contacts || [] %>
        <% outgoing = @outgoing_requests || [] %>
        <% outgoing_ids = Enum.map(outgoing, & &1.friend_user_id) %>

        <%= if @search_query != "" do %>
          <%!-- Search Results --%>
          <%= if @search_results == [] do %>
            <p class="text-center py-8 text-white/30 text-sm">No results</p>
          <% else %>
            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
              <%= for user <- @search_results do %>
                  <% 
                    is_self = user.id == @current_user.id
                    is_contact = Enum.any?(contacts, fn c -> 
                      u = if Map.has_key?(c, :user), do: c.user, else: c
                      u.id == user.id 
                    end)
                    is_pending = user.id in outgoing_ids
                    outgoing_trust_ids = Enum.map(@outgoing_trust_requests || [], & &1.trusted_user_id)
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
                    is_trust_pending={user.id in outgoing_trust_ids}
                    mode={@mode}
                    member_ids={@member_ids}
                    is_admin={@is_admin}
                  />
              <% end %>
            </div>
          <% end %>
        <% else %>
          <%!-- 1. INCOMING REQUESTS (Friend & Trust) --%>
          <% friend_requests = @pending_friend_requests || [] %>
          <% trust_requests = @incoming_trust_requests || [] %>
          
          <%= if Enum.any?(friend_requests) || Enum.any?(trust_requests) do %>
            <div class="mb-6 space-y-3">
              <%= if Enum.any?(friend_requests) do %>
                <div>
                  <div class="flex items-center gap-2 mb-2">
                    <svg class="w-3.5 h-3.5 text-blue-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M18 9v3m0 0v3m0-3h3m-3 0h-3m-2-5a4 4 0 11-8 0 4 4 0 018 0zM3 20a6 6 0 0112 0v1H3v-1z" />
                    </svg>
                    <span class="text-[10px] font-semibold text-blue-400 uppercase tracking-wider">Incoming Requests</span>
                  </div>
                  <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
                    <%= for fr <- friend_requests do %>
                      <% user = if Map.has_key?(fr, :user), do: fr.user, else: fr %>
                      <.friend_request_row user={user} />
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>

          <%!-- 2. YOUR PEOPLE (Contacts) - Sorted by activity --%>
          <div class="mb-6">
            <div class="flex items-center gap-2 mb-2">
              <svg class="w-3.5 h-3.5 text-white/50" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z" />
              </svg>
              <span class="text-[10px] font-medium text-white/40 uppercase tracking-wider">Your People ({length(contacts)})</span>
            </div>
            <%= if Enum.any?(contacts) do %>
              <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
                <%= for contact <- contacts do %>
                  <% 
                    user = if Map.has_key?(contact, :user), do: contact.user, else: contact 
                    outgoing_trust_ids = Enum.map(@outgoing_trust_requests || [], & &1.trusted_user_id)
                  %>
                  <.person_row 
                    user={user} 
                    status={:connected}
                    online={@online_friend_ids && MapSet.member?(@online_friend_ids, user.id)}
                    is_recovery={false}
                    is_trust_pending={user.id in outgoing_trust_ids}
                    mode={@mode}
                    member_ids={@member_ids}
                    is_admin={@is_admin}
                  />
                <% end %>
              </div>
            <% else %>
              <div class="text-center py-8 bg-white/5 rounded-xl border border-white/5">
                <div class="w-12 h-12 mx-auto mb-3 rounded-full bg-white/5 flex items-center justify-center">
                  <svg class="w-6 h-6 text-white/30" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z" />
                  </svg>
                </div>
                <p class="text-white/40 text-sm">No contacts yet</p>
              </div>
            <% end %>
          </div>
          
          <%!-- 3. OUTGOING PENDING (Sent Requests) --%>
          <%= if Enum.any?(outgoing) do %>
            <div class="mb-4">
              <div class="flex items-center gap-2 mb-2">
                <svg class="w-3.5 h-3.5 text-white/50" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
                <span class="text-[10px] font-medium text-white/40 uppercase tracking-wider">Pending Sent Requests</span>
              </div>
              <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
                <%= for req <- outgoing do %>
                  <% user = if Map.has_key?(req, :friend_user), do: req.friend_user, else: req %>
                  <.pending_connection_row user={user} />
                <% end %>
              </div>
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  # ============================================================================
  # AVATAR COMPONENT
  # Handles image vs initials fallback
  # ============================================================================

  attr :user, :map, required: true
  attr :class, :string, default: "w-10 h-10"
  attr :online, :boolean, default: false

  def avatar(assigns) do
    ~H"""
    <div
      class={"#{@class} rounded-full flex items-center justify-center text-sm font-bold shrink-0 relative overflow-hidden #{if @online, do: "avatar-online", else: ""}"}
      style={unless has_avatar?(@user), do: "background-color: #{friend_color(@user)};"}
    >
      <%= if has_avatar?(@user) do %>
        <img
          src={avatar_url(@user)}
          class="w-full h-full object-cover"
          alt={@user.username}
        />
      <% else %>
        <span class="text-white">{String.first(@user.username) |> String.upcase()}</span>
      <% end %>
    </div>
    """
  end

  defp has_avatar?(user) do
    user.avatar_url_thumb || user.avatar_url
  end

  defp avatar_url(user) do
    user.avatar_url_thumb || user.avatar_url
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
      <.avatar user={@user} online={@online} />

      <%!-- Name with shield --%>
      <div class="flex-1 min-w-0">
        <div class="flex items-center gap-1.5">
          <span class="text-sm text-white break-all">@{@user.username}</span>
          <.shield_icon class="w-3.5 h-3.5 text-green-400 shrink-0" />
        </div>
        <%= if @online do %>
          <span class="text-[10px] text-green-400/70">Here now</span>
        <% end %>
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
        <span class="text-sm text-white break-all">@{@user.username}</span>
        <span class="block text-[10px] text-white/40">pending</span>
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
      <.avatar user={@user} />

      <%!-- Name --%>
      <div class="flex-1 min-w-0">
        <span class="text-sm text-white break-all">@{@user.username}</span>
        <span class="block text-[10px] text-yellow-400/70">wants you as recovery</span>
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
      <.avatar user={@user} />

      <%!-- Name --%>
      <div class="flex-1 min-w-0">
        <span class="text-sm text-white break-all">@{@user.username}</span>
        <span class="block text-[10px] text-purple-400/70">awaiting response</span>
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
      <.avatar user={@user} />

      <%!-- Name --%>
      <div class="flex-1 min-w-0">
        <span class="text-sm text-white break-all">@{@user.username}</span>
        <span class="block text-[10px] text-blue-400/70">wants to connect</span>
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
  attr :is_trust_pending, :boolean, default: false
  attr :mode, :atom, default: :add_contact
  attr :member_ids, :any, default: %MapSet{}
  attr :is_admin, :boolean, default: false

  def person_row(assigns) do

    ~H"""
    <div class="flex items-center gap-3 py-2 px-3 group md:bg-white/5 md:rounded-xl md:border md:border-white/5 md:hover:border-white/10 transition-all">
      <%!-- Avatar + Name (clickable to open DM) --%>
      <div
        class={"flex items-center gap-3 flex-1 min-w-0 cursor-pointer rounded-lg px-2 py-1 -mx-2 -my-1 #{if @status == :connected, do: "hover:bg-white/5 transition-colors", else: ""}"}
        phx-click={if @status == :connected, do: "open_dm", else: nil}
        phx-value-user_id={@user.id}
      >
        <%!-- Avatar --%>
        <.avatar user={@user} online={@online} />

        <%!-- Name and status stacked for better mobile layout --%>
        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-1.5">
            <span class="text-sm text-white break-all">@{@user.username}</span>
            <%= if @is_recovery && @status == :connected do %>
              <.shield_icon class="w-3.5 h-3.5 text-green-400 shrink-0" />
            <% end %>
          </div>
          <%= if @online do %>
            <span class="text-[10px] text-green-400/70">Here now</span>
          <% end %>
        </div>
      </div>

      <%!-- Actions - more compact on mobile --%>
      <div class="flex items-center gap-1 shrink-0">
          <%= case @status do %>
            <% :self -> %>
              <span class="text-xs text-white/30">You</span>
            <% :connected -> %>
              <%!-- Remove friend --%>
              <button
                phx-click="remove_contact"
                phx-value-user_id={@user.id}
                data-confirm={"Are you sure you want to remove @#{@user.username} from your contacts?"}
                class="text-xs text-red-400/60 hover:text-red-400 transition-colors cursor-pointer px-1"
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
              data-confirm={"DELETE user @#{@user.username} and ALL their content? This cannot be undone!"}
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
