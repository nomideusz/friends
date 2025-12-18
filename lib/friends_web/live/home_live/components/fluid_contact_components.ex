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
  attr :incoming_trust_requests, :list, default: []
  attr :room, :map, default: nil
  attr :room_members, :list, default: []

  def contact_search_sheet(assigns) do
    mode = assigns[:mode] || :add_contact
    trusted_ids = assigns[:trusted_friend_ids] || []

    assigns = assigns
      |> assign(:mode, mode)
      |> assign(:trusted_ids, trusted_ids)
      
    # Pre-calculate room member IDs for invite mode
    member_ids = if mode == :invite and assigns[:room_members] do
      Enum.map(assigns.room_members, & &1.user.id) |> MapSet.new()
    else
      MapSet.new()
    end
    
    assigns = assign(assigns, :member_ids, member_ids)

    ~H"""
    <%= if @show do %>
      <div id="people-sheet" class="fixed inset-0 z-[200]" phx-window-keydown="close_contact_search" phx-key="escape">
        <%!-- Backdrop --%>
        <div
          class="absolute inset-0 bg-black/70 backdrop-blur-sm animate-in fade-in duration-200"
          phx-click="close_contact_search"
        ></div>

        <%!-- Modal --%>
        <div class="absolute inset-x-0 bottom-0 z-10 flex justify-center animate-in slide-in-from-bottom duration-300">
          <div class="w-full max-w-lg bg-neutral-900/95 backdrop-blur-xl border-t border-x border-white/10 rounded-t-3xl shadow-2xl max-h-[80vh] flex flex-col">
            <%!-- Handle --%>
            <div class="py-3 flex justify-center cursor-pointer" phx-click="close_contact_search">
              <div class="w-10 h-1 rounded-full bg-white/20"></div>
            </div>

            <%!-- Header (Invite Mode) --%>
            <%= if @mode == :invite and @room do %>
              <div class="px-4 pb-2">
                <h3 class="text-sm font-medium text-white/70">Invite to {@room.name || @room.code}</h3>
              </div>
            <% end %>

            <%!-- Search --%>
            <div class="px-4 pb-3">
              <input
                type="text"
                name="contact_search"
                value={@search_query}
                placeholder={
                  case @mode do
                    :add_contact -> "Search by username..."
                    :invite -> "Search friends to invite..."
                    _ -> "Filter people..."
                  end
                }
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
              <% outgoing_ids = Enum.map(outgoing, & &1.trusted_user_id) %>
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
                      />
                    <% end %>
                  </div>
                <% end %>
              <% else %>
                <%!-- Pending Trust Requests (incoming) --%>
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
                
                <%!-- Recovery Contacts Section --%>
                <div class="mb-4">
                  <div class="flex items-center justify-between mb-2">
                    <span class="text-[10px] font-medium text-white/40 uppercase tracking-wider">Recovery Contacts</span>
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
                  <% else %>
                    <p class="text-xs text-white/30 mb-3">No recovery contacts yet</p>
                  <% end %>
                </div>
                
                <%!-- Your People (excluding recovery contacts) --%>
                <% non_recovery_contacts = Enum.reject(contacts, fn c -> 
                  u = if Map.has_key?(c, :user), do: c.user, else: c
                  u.id in @trusted_ids
                end) %>
                <div class="text-[10px] font-medium text-white/40 uppercase tracking-wider mb-2">Your People</div>
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
                      />
                    <% end %>
                  </div>
                <% else %>
                  <p class="text-center py-4 text-white/30 text-sm">Search to add people</p>
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
        <%= for i <- 1..5 do %>
          <div class={"w-1.5 h-3 rounded-sm #{if i <= @count, do: "bg-green-400", else: "bg-white/10"}"}></div>
        <% end %>
      </div>
      <span class={"text-[10px] #{if @count >= 4, do: "text-green-400", else: "text-white/30"}"}>
        <%= cond do %>
          <% @count >= 4 -> %>Protected
          <% @count >= 2 -> %>{@count}/4
          <% @count > 0 -> %>Weak
          <% true -> %>None
        <% end %>
      </span>
    </div>
    """
  end

  # ============================================================================
  # RECOVERY CONTACT ROW
  # For the recovery contacts list
  # ============================================================================

  attr :user, :map, required: true
  attr :online, :boolean, default: false

  def recovery_contact_row(assigns) do
    ~H"""
    <div class="flex items-center gap-3 py-2 px-2 rounded-xl bg-green-500/10 border border-green-500/20">
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
            <span class="w-1.5 h-1.5 rounded-full bg-green-400"></span>
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
            <span class="w-1.5 h-1.5 rounded-full bg-green-400"></span>
          <% end %>
          <%= if @is_recovery && @status == :connected do %>
            <.shield_icon class="w-3.5 h-3.5 text-green-400" />
          <% end %>
        </div>
      </div>

      <%!-- Actions --%>
      <div class="flex items-center gap-2">
        <%= if @mode == :invite do %>
           <% is_member = MapSet.member?(@member_ids, @user.id) %>
           <%= if is_member do %>
             <span class="text-xs text-white/30">Member</span>
           <% else %>
             <button
               phx-click="invite_friend_to_room"
               phx-value-friend_id={@user.id}
               class="px-3 py-1.5 bg-white/10 hover:bg-white/20 text-white rounded-lg text-xs font-medium transition-colors cursor-pointer"
             >
               Invite
             </button>
           <% end %>
        <% else %>
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
        <% end %>
      </div>
    </div>
    """
  end
end
