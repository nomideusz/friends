defmodule FriendsWeb.HomeLive.Components.FluidRoomSheetComponents do
  @moduledoc """
  Bottom sheet components for private rooms.
  Includes members sheet, add content sheet, and room settings sheet.
  """
  use FriendsWeb, :html
  import FriendsWeb.HomeLive.Helpers

  # ============================================================================
  # UNIFIED GROUP SHEET
  # Combines members list + invite + share link in one sheet
  # ============================================================================

  attr :show, :boolean, default: false
  attr :room, :map, required: true
  attr :room_members, :list, default: []
  attr :current_user, :map, required: true
  attr :friends, :list, default: []
  attr :group_search, :string, default: ""
  attr :viewers, :list, default: []

  def group_sheet(assigns) do
    # Build member IDs set
    member_ids = MapSet.new(Enum.map(assigns.room_members, & &1.user_id))
    # Build online IDs set - only count members currently viewing
    all_viewer_ids = MapSet.new(Enum.map(assigns.viewers, fn v -> v.user_id end))
    # Always include current user if they're a member (presence may not have caught up yet)
    current_user_id = assigns.current_user && assigns.current_user.id
    all_viewer_ids = if current_user_id && MapSet.member?(member_ids, current_user_id) do
      MapSet.put(all_viewer_ids, current_user_id)
    else
      all_viewer_ids
    end
    online_ids = MapSet.intersection(all_viewer_ids, member_ids)

    
    # Filter members by search
    filtered_members = 
      if assigns.group_search == "" do
        assigns.room_members
      else
        query = String.downcase(assigns.group_search)
        Enum.filter(assigns.room_members, fn m ->
          String.contains?(String.downcase(m.user.username), query)
        end)
      end
    
    # Sort: Owner > Admin > Others, then by username
    filtered_members = 
      filtered_members
      |> Enum.sort_by(fn m -> 
        is_owner = m.user_id == assigns.room.owner_id
        
        role_priority = case m.role do
          "admin" -> 1
          "member" -> 2
          _ -> 3
        end
        
        # Priority: 0=Owner, 1=Admin, 2=Member, 3=Other
        sort_rank = if is_owner, do: 0, else: role_priority
        
        {sort_rank, String.downcase(m.user.username)}
      end)
    
    # Filter friends (non-members) by search
    non_member_friends = Enum.reject(assigns.friends, fn f -> 
      MapSet.member?(member_ids, f.user.id)
    end)
    
    filtered_friends = 
      if assigns.group_search == "" do
        non_member_friends
      else
        query = String.downcase(assigns.group_search)
        Enum.filter(non_member_friends, fn f ->
          String.contains?(String.downcase(f.user.username), query)
        end)
      end
    
    is_owner = assigns.room.owner_id == assigns.current_user.id
    
    # Get current user's role in this room
    current_user_member = Enum.find(assigns.room_members, fn m -> m.user_id == assigns.current_user.id end)
    current_user_role = if current_user_member, do: current_user_member.role, else: "member"
    
    assigns = assigns
      |> assign(:online_ids, online_ids)
      |> assign(:filtered_members, filtered_members)
      |> assign(:filtered_friends, filtered_friends)
      |> assign(:is_owner, is_owner)
      |> assign(:current_user_role, current_user_role)

    ~H"""
    <%= if @show do %>
      <div class="fixed inset-0 z-[300]" phx-window-keydown="close_group_sheet" phx-key="escape">
        <%!-- Backdrop --%>
        <div
          class="absolute inset-0 bg-black/70 backdrop-blur-sm animate-in fade-in duration-200"
          phx-click="close_group_sheet"
        ></div>

        <%!-- Sheet --%>
        <div class="absolute inset-x-0 bottom-0 z-10 flex justify-center animate-in slide-in-from-bottom duration-300">
          <div class="w-full max-w-lg bg-neutral-900/95 backdrop-blur-xl border-t border-x border-white/10 rounded-t-3xl shadow-2xl max-h-[85vh] flex flex-col"
            phx-click-away="close_group_sheet"
          >
            <%!-- Handle --%>
            <div class="py-3 flex justify-center cursor-pointer" phx-click="close_group_sheet">
              <div class="w-10 h-1 rounded-full bg-white/20"></div>
            </div>

            <%!-- Search --%>
            <div class="px-4 pb-3">
              <input
                type="text"
                name="group_search"
                value={@group_search}
                placeholder="Search..."
                phx-keyup="group_search"
                phx-debounce="150"
                autocomplete="off"
                class="w-full bg-white/5 border border-white/10 rounded-xl px-4 py-3 text-white placeholder-white/30 focus:border-white/30 focus:outline-none text-sm"
              />
            </div>

            <%!-- Content --%>
            <div class="flex-1 overflow-y-auto px-4 pb-4 space-y-4">
              <%!-- MEMBERS SECTION --%>
              <div>
                <div class="text-[10px] font-bold text-white/40 uppercase tracking-widest mb-2">
                  Members ({length(@room_members)})
                </div>
                <div class="space-y-1">
                  <%= for member <- @filtered_members do %>
                    <% is_online = MapSet.member?(@online_ids, member.user_id) %>
                    <% is_self = member.user_id == @current_user.id %>
                    <div class="flex items-center gap-3 p-2.5 rounded-xl bg-white/5 border border-white/5">
                      <%!-- Avatar with presence glow --%>
                      <div 
                        class={"w-9 h-9 rounded-full flex items-center justify-center text-xs font-bold text-white #{if is_online, do: "", else: "opacity-70"}"}
                        style={"background-color: #{member_color(member)}; #{if is_online, do: "box-shadow: 0 0 8px 3px rgba(74, 222, 128, 0.6); animation: presence-breathe 3s ease-in-out infinite;", else: ""}"}
                      >
                        {String.first(member.user.username) |> String.upcase()}
                      </div>
                      
                      <%!-- Info --%>
                      <div class="flex-1 min-w-0">
                        <div class="flex items-center gap-2">
                          <span class="text-sm font-medium text-white truncate">@{member.user.username}</span>
                          <%= if @room.owner_id == member.user_id do %>
                            <span class="text-[9px] text-yellow-500 bg-yellow-500/10 px-1.5 py-0.5 rounded border border-yellow-500/20">Owner</span>
                          <% end %>
                          <%= if member.role == "admin" do %>
                            <span class="text-[9px] text-blue-400 bg-blue-500/10 px-1.5 py-0.5 rounded border border-blue-500/20">Admin</span>
                          <% end %>
                          <%= if is_online do %>
                            <span class="text-[9px] text-green-400">online</span>
                          <% end %>
                        </div>
                      </div>
                      
                      <%!-- Actions (dropdown menu) --%>
                      <%= if (@is_owner or member.role == "member") and not is_self and @room.owner_id != member.user_id do %>
                        <div class="flex items-center gap-1">
                          <%!-- Make/Remove Admin (owner only) --%>
                          <%= if @is_owner do %>
                            <%= if member.role == "admin" do %>
                              <button
                                phx-click="remove_admin"
                                phx-value-user_id={member.user_id}
                                class="text-[10px] text-blue-400/70 hover:text-blue-400 transition-colors px-2 py-1 cursor-pointer"
                              >
                                ✕ Admin
                              </button>
                            <% else %>
                              <button
                                phx-click="make_admin"
                                phx-value-user_id={member.user_id}
                                class="text-[10px] text-blue-400/70 hover:text-blue-400 transition-colors px-2 py-1 cursor-pointer"
                              >
                                + Admin
                              </button>
                            <% end %>
                          <% end %>
                          
                          <%!-- Remove (owner or admin can remove members) --%>
                          <%= if @is_owner or (@current_user_role == "admin" and member.role == "member") do %>
                            <button
                              phx-click="remove_member"
                              phx-value-user_id={member.user_id}
                              data-confirm={"Remove @#{member.user.username}?"}
                              class="text-[10px] text-red-400/70 hover:text-red-400 transition-colors px-2 py-1 cursor-pointer"
                            >
                              Remove
                            </button>
                          <% end %>
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              </div>

              <%!-- INVITE SECTION (if not DM) --%>
              <%= if @room.room_type != "dm" and @filtered_friends != [] do %>
                <div>
                  <div class="text-[10px] font-bold text-white/40 uppercase tracking-widest mb-2">
                    Invite
                  </div>
                  <div class="space-y-1">
                    <%= for friend <- @filtered_friends do %>
                      <div class="flex items-center gap-3 p-2.5 rounded-xl bg-white/5 border border-white/5">
                        <div 
                          class="w-9 h-9 rounded-full flex items-center justify-center text-xs font-bold text-white border border-white/20"
                          style={"background-color: #{member_color(friend)};"}
                        >
                          {String.first(friend.user.username) |> String.upcase()}
                        </div>
                        <span class="flex-1 text-sm font-medium text-white truncate">@{friend.user.username}</span>
                        <button
                          phx-click="invite_to_room"
                          phx-value-user_id={friend.user.id}
                          class="px-3 py-1.5 bg-white/10 hover:bg-white/20 text-white rounded-lg text-xs font-medium transition-colors cursor-pointer"
                        >
                          Invite
                        </button>
                      </div>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>

            <%!-- Share Link (bottom) --%>
            <%= if @room.room_type != "dm" do %>
              <div class="px-4 py-3 border-t border-white/5">
                <div class="flex items-center gap-2 bg-white/5 border border-white/10 rounded-xl px-3 py-2">
                  <svg class="w-4 h-4 text-white/30 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1" />
                  </svg>
                  <code class="flex-1 text-xs text-white/50 truncate font-mono">
                    {url(~p"/r/#{@room.code}")}
                  </code>
                  <button
                    id="group-sheet-copy"
                    phx-hook="CopyToClipboard"
                    data-copy-text={url(~p"/r/#{@room.code}")}
                    class="px-3 py-1 bg-white/10 hover:bg-white/20 text-white rounded-lg text-xs font-medium transition-colors cursor-pointer"
                  >
                    Copy
                  </button>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  # ============================================================================
  # ROOM ADD SHEET
  # Bottom sheet for adding content from room toolbar's + button
  # ============================================================================

  attr :show, :boolean, default: false
  attr :room, :map, required: true
  attr :uploads, :map, default: nil

  def room_add_sheet(assigns) do
    ~H"""
    <%= if @show do %>
      <div class="fixed inset-0 z-[200]" phx-window-keydown="toggle_add_menu" phx-key="escape">
        <%!-- Backdrop --%>
        <div
          class="absolute inset-0 bg-black/70 backdrop-blur-sm animate-in fade-in duration-200"
          phx-click="toggle_add_menu"
        ></div>

        <%!-- Sheet --%>
        <div class="absolute inset-x-0 bottom-0 z-10 flex justify-center animate-in slide-in-from-bottom duration-300">
          <div class="w-full max-w-lg bg-neutral-900/95 backdrop-blur-xl border-t border-x border-white/10 rounded-t-3xl shadow-2xl">
            <%!-- Handle --%>
            <div class="py-3 flex justify-center cursor-pointer" phx-click="toggle_add_menu">
              <div class="w-10 h-1 rounded-full bg-white/20"></div>
            </div>

            <%!-- Options --%>
            <div class="px-4 pb-8 grid grid-cols-3 gap-4">
              <%!-- Photo --%>
              <form id="room-add-sheet-upload" phx-change="validate" phx-submit="save" class="contents">
                <label class="flex flex-col items-center gap-2 p-4 rounded-2xl bg-white/5 border border-white/10 hover:bg-white/10 hover:border-white/20 transition-all cursor-pointer">
                  <div class="w-12 h-12 rounded-full bg-gradient-to-br from-pink-500 to-rose-600 flex items-center justify-center">
                    <svg class="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
                    </svg>
                  </div>
                  <span class="text-xs text-white/70">Photo</span>
                  <%= if @uploads && @uploads[:photo] do %>
                    <.live_file_input upload={@uploads.photo} class="sr-only" />
                  <% end %>
                </label>
              </form>

              <%!-- Note --%>
              <button
                type="button"
                phx-click="open_room_note_modal"
                class="flex flex-col items-center gap-2 p-4 rounded-2xl bg-white/5 border border-white/10 hover:bg-white/10 hover:border-white/20 transition-all cursor-pointer"
              >
                <div class="w-12 h-12 rounded-full bg-gradient-to-br from-amber-500 to-orange-600 flex items-center justify-center">
                  <svg class="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                  </svg>
                </div>
                <span class="text-xs text-white/70">Note</span>
              </button>

              <%!-- Voice (goes to chat) --%>
              <button
                id="room-add-sheet-voice"
                phx-hook="RoomVoiceRecorder"
                data-room-id={@room.id}
                class="flex flex-col items-center gap-2 p-4 rounded-2xl bg-white/5 border border-white/10 hover:bg-white/10 hover:border-white/20 transition-all cursor-pointer"
              >
                <div class="w-12 h-12 rounded-full bg-gradient-to-br from-purple-500 to-violet-600 flex items-center justify-center">
                  <svg class="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z" />
                  </svg>
                </div>
                <span class="text-xs text-white/70">Voice</span>
              </button>
            </div>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  # ============================================================================
  # ROOM SETTINGS SHEET
  # Opened from "More" button on room toolbar
  # ============================================================================

  attr :show, :boolean, default: false
  attr :room, :map, required: true
  attr :current_user, :map, required: true

  def room_settings_sheet(assigns) do
    ~H"""
    <%= if @show do %>
      <div class="fixed inset-0 z-[200]" phx-window-keydown="open_room_settings" phx-key="escape">
        <%!-- Backdrop --%>
        <div
          class="absolute inset-0 bg-black/70 backdrop-blur-sm animate-in fade-in duration-200"
          phx-click="open_room_settings"
        ></div>

        <%!-- Sheet --%>
        <div class="absolute inset-x-0 bottom-0 z-10 flex justify-center animate-in slide-in-from-bottom duration-300">
          <div class="w-full max-w-lg bg-neutral-900/95 backdrop-blur-xl border-t border-x border-white/10 rounded-t-3xl shadow-2xl">
            <%!-- Handle --%>
            <div class="py-3 flex justify-center cursor-pointer" phx-click="open_room_settings">
              <div class="w-10 h-1 rounded-full bg-white/20"></div>
            </div>

            <%!-- Content --%>
            <div class="px-4 pb-8 space-y-2">
              <h3 class="text-white text-lg font-bold mb-4 px-2"><%= @room.name || "Untitled Group" %></h3>

              <button
                phx-click={JS.push("close_room_settings") |> JS.push("open_contacts_sheet")}
                class="w-full flex items-center gap-4 p-4 rounded-xl bg-white/5 border border-white/10 hover:bg-white/10 transition-all text-left"
              >
                <div class="w-10 h-10 rounded-full bg-blue-500/20 flex items-center justify-center text-blue-400">
                  <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M18 9v3m0 0v3m0-3h3m-3 0h-3m-2-5a4 4 0 11-8 0 4 4 0 018 0zM3 20a6 6 0 0112 0v1H3v-1z" />
                  </svg>
                </div>
                <div class="flex-1">
                  <div class="text-white font-medium">Invite People</div>
                  <div class="text-white/40 text-xs">Add members to this group</div>
                </div>
              </button>

              <button
                phx-click="remove_room_member"
                phx-value-user_id={@current_user.id}
                data-confirm="Are you sure you want to leave this group?"
                class="w-full flex items-center gap-4 p-4 rounded-xl bg-white/5 border border-white/10 hover:bg-red-500/10 hover:border-red-500/30 transition-all text-left group"
              >
                <div class="w-10 h-10 rounded-full bg-red-500/10 flex items-center justify-center text-red-400 group-hover:text-red-500">
                  <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                     <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1" />
                  </svg>
                </div>
                <div class="flex-1">
                  <div class="text-red-400 font-medium group-hover:text-red-500">Leave Group</div>
                  <div class="text-white/40 text-xs">You can rejoin via invite link</div>
                </div>
              </button>

              <%= if @room.owner_id == @current_user.id do %>
                <button
                   disabled
                   class="w-full flex items-center gap-4 p-4 rounded-xl bg-white/5 border border-white/10 opacity-50 cursor-not-allowed text-left"
                   title="Deletion not implemented yet"
                >
                  <div class="w-10 h-10 rounded-full bg-red-500/10 flex items-center justify-center text-red-500">
                    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                    </svg>
                  </div>
                  <div class="flex-1">
                    <div class="text-red-500 font-medium">Delete Group</div>
                    <div class="text-white/40 text-xs">Permanently remove this group</div>
                  </div>
                </button>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    <% end %>
    """
  end
end
