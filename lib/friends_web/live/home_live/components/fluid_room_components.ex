defmodule FriendsWeb.HomeLive.Components.FluidRoomComponents do
  @moduledoc """
  Fluid design components for private rooms.
  Content-first, contextual chat, minimal chrome.
  
  This module provides the core room layout and imports related components from:
  - FluidRoomChatComponents - chat panels and input
  - FluidRoomSheetComponents - bottom sheets (members, settings, add)
  - FluidRoomContentComponents - content grid and items
  """
  use FriendsWeb, :html
  import FriendsWeb.HomeLive.Helpers

  # Import sub-modules for component reuse
  import FriendsWeb.HomeLive.Components.FluidRoomChatComponents
  import FriendsWeb.HomeLive.Components.FluidRoomSheetComponents
  import FriendsWeb.HomeLive.Components.FluidRoomContentComponents

  # ============================================================================
  # FLUID ROOM LAYOUT
  # The main wrapper for private rooms with content-first approach
  # ============================================================================

  attr :room, :map, required: true
  attr :current_user, :map, required: true
  attr :room_members, :list, default: []
  attr :room_messages, :list, default: []
  attr :items, :list, required: true
  attr :item_count, :integer, default: 0
  attr :new_chat_message, :string, default: ""
  attr :uploads, :map, default: nil
  attr :uploading, :boolean, default: false
  attr :recording_voice, :boolean, default: false
  attr :no_more_items, :boolean, default: false
  attr :show_members_panel, :boolean, default: false
  attr :chat_expanded, :boolean, default: false
  attr :typing_users, :map, default: %{}
  attr :friends, :list, default: []
  attr :viewers, :list, default: []
  attr :context_menu_member_id, :integer, default: nil
  attr :show_group_sheet, :boolean, default: false
  attr :group_search, :string, default: ""
  attr :show_chat, :boolean, default: true
  attr :show_add_menu, :boolean, default: false

  def fluid_room(assigns) do
    # Calculate energy level based on number of online viewers (1-5 scale)
    viewer_count = length(assigns.viewers)
    energy_level = min(5, max(1, viewer_count))
    assigns = assign(assigns, :energy_level, energy_level)

    ~H"""
    <div
      id="fluid-room"
      class="fixed inset-0 bg-black flex flex-col z-[100] group-energy"
      data-energy={@energy_level}
      phx-hook="FriendsApp"
      phx-window-keydown="handle_keydown"
    >
      <%!-- Minimal Header --%>
      <.fluid_room_header
        room={@room}
        room_members={@room_members}
        current_user={@current_user}
        show_members_panel={@show_members_panel}
        viewers={@viewers}
        context_menu_member_id={@context_menu_member_id}
      />

      <%!-- Content Area (scrollable, adjusts for chat) --%>
      <div class={"flex-1 overflow-y-auto overflow-x-hidden scrollbar-hide pt-20 transition-all duration-300 #{if @chat_expanded, do: "pb-[50vh]", else: "pb-48"}"}>
        <%= if @item_count == 0 do %>
          <.fluid_empty_state />
        <% else %>
          <.fluid_content_grid items={@items} room={@room} current_user={@current_user} />
        <% end %>

        <%!-- Load More --%>
        <%= unless @no_more_items do %>
          <div class="flex justify-center py-8">
            <button
              type="button"
              phx-click="load_more"
              phx-disable-with="..."
              class="w-10 h-10 rounded-full border border-white/20 text-white/40 hover:border-white/40 hover:text-white/70 transition-colors cursor-pointer flex items-center justify-center"
            >
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
              </svg>
            </button>
          </div>
        <% end %>
      </div>

      <%!-- Inline Chat Panel (fixed at bottom) --%>
      <.inline_chat_panel
        room={@room}
        room_messages={@room_messages}
        current_user={@current_user}
        new_chat_message={@new_chat_message}
        typing_users={@typing_users}
        expanded={@chat_expanded}
        uploading={@uploading}
      />
    </div>
    """
  end

  # ============================================================================
  # MINIMAL HEADER
  # Floats above content, tap for members
  # ============================================================================

  attr :room, :map, required: true
  attr :room_members, :list, default: []
  attr :current_user, :map, required: true
  attr :show_members_panel, :boolean, default: false
  attr :viewers, :list, default: []
  attr :context_menu_member_id, :integer, default: nil

  def fluid_room_header(assigns) do
    # Build set of member IDs
    member_ids = MapSet.new(Enum.map(assigns.room_members, & &1.user_id))
    # Build set of online user IDs from presence - only count members
    # Normalize IDs to integers (presence metadata often uses strings)
    all_viewer_ids = 
      assigns.viewers
      |> Enum.map(fn v -> 
        case v.user_id do
          id when is_integer(id) -> id
          "user-" <> id_str -> String.to_integer(id_str)
          id when is_binary(id) -> String.to_integer(id)
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()
    # Always include current user if they're a member (presence may not have caught up yet)
    current_user_id = assigns.current_user && assigns.current_user.id
    all_viewer_ids = if current_user_id && MapSet.member?(member_ids, current_user_id) do
      MapSet.put(all_viewer_ids, current_user_id)
    else
      all_viewer_ids
    end
    online_ids = MapSet.intersection(all_viewer_ids, member_ids)
    
    # Sort members: online first, then by username
    sorted_members = Enum.sort_by(assigns.room_members, fn m ->
      {!MapSet.member?(online_ids, m.user_id), m.user.username}
    end)
    
    assigns = assigns
      |> assign(:online_ids, online_ids)
      |> assign(:sorted_members, sorted_members)

    ~H"""
    <div class="absolute top-0 inset-x-0 z-50 pl-4 pr-4 pt-3 pb-6 flex items-center justify-between bg-gradient-to-b from-black/80 via-black/40 to-transparent backdrop-blur-sm transition-all duration-300">
      <%!-- Back + Room Name --%>
      <div class="flex items-center gap-3 min-w-0">
        <.link
          navigate="/"
          class="w-8 h-8 rounded-full flex items-center justify-center bg-white/5 border border-white/10 text-white/70 hover:text-white hover:bg-white/10 transition-colors shrink-0"
        >
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M15 19l-7-7 7-7" />
          </svg>
        </.link>

        <%!-- Room info (C: clickable to open members) --%>
        <button
          phx-click="toggle_members_panel"
          class="flex flex-col items-start truncate hover:opacity-80 transition-opacity cursor-pointer text-left flex-1 min-w-0"
        >
          <div class="flex items-center gap-2 max-w-full">
            <span class="text-sm sm:text-base font-bold text-white truncate leading-tight max-w-[40vw] sm:max-w-none">
              {@room.name || @room.code}
            </span>
            <%!-- Lock icon for private room --%>
            <svg class="w-3 h-3 text-white/30 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
            </svg>
          </div>
          <span class="text-[10px] font-medium text-white/40 truncate">
            {length(@room_members)} members • {MapSet.size(@online_ids)} online
          </span>
        </button>
      </div>


      <%!-- Members Circle (like main page nav) --%>
      <div class="flex items-center gap-2 pl-2 shrink-0">
        <button
          phx-click="toggle_members_panel"
          class="group relative cursor-pointer"
          title="View members"
        >
          <%!-- Member count circle with glow when online --%>
          <div class={"w-10 h-10 rounded-full bg-black/40 backdrop-blur-xl border border-white/10 shadow-lg
            flex items-center justify-center text-sm font-bold transition-all duration-300
            hover:bg-white/10 hover:border-white/20 hover:scale-105 active:scale-95
            #{if MapSet.size(@online_ids) > 0, do: "avatar-online text-green-400", else: "text-white/80"}"}>
            {length(@room_members)}
          </div>
          
          <%!-- Live online count below (green, like main page) --%>
          <%= if MapSet.size(@online_ids) > 0 do %>
            <div class="absolute -bottom-5 left-1/2 -translate-x-1/2 text-[10px] font-medium text-green-400">
              {MapSet.size(@online_ids)}
            </div>
          <% end %>
        </button>
      </div>
    </div>
    """
  end

  # ============================================================================
  # MEMBER CONTEXT MENU
  # Minimal popup when clicking on member avatar
  # ============================================================================

  attr :member, :map, required: true
  attr :room, :map, required: true
  attr :current_user, :map, required: true
  attr :is_online, :boolean, default: false

  def member_context_menu(assigns) do
    is_owner = assigns.room.owner_id == assigns.current_user.id
    is_self = assigns.member.user_id == assigns.current_user.id
    assigns = assigns
      |> assign(:is_owner, is_owner)
      |> assign(:is_self, is_self)

    ~H"""
    <%!-- Backdrop to close --%>
    <div 
      class="fixed inset-0 z-40" 
      phx-click="close_member_menu"
    ></div>

    <%!-- Menu popup --%>
    <div class="absolute top-10 left-1/2 -translate-x-1/2 z-50 w-40 bg-neutral-900/95 backdrop-blur-xl border border-white/10 rounded-xl shadow-2xl overflow-hidden animate-in fade-in zoom-in-95 duration-150">
      <%!-- Header with username --%>
      <div class="px-3 py-2 border-b border-white/5">
        <div class="flex items-center gap-2">
          <span class="text-xs font-medium text-white truncate">@{@member.user.username}</span>
          <%= if @is_online do %>
            <span class="w-1.5 h-1.5 rounded-full bg-green-400"></span>
          <% end %>
        </div>
      </div>

      <%!-- Actions --%>
      <div class="py-1">
        <%!-- View Profile / Message (future) --%>
        <button
          phx-click="close_member_menu"
          class="w-full px-3 py-2 text-left text-xs text-white/70 hover:bg-white/10 transition-colors"
        >
          View profile
        </button>

        <%!-- Remove (owner only, not self) --%>
        <%= if @is_owner and not @is_self do %>
          <button
            phx-click="remove_member"
            phx-value-user_id={@member.user_id}
            data-confirm={"Remove @#{@member.user.username}?"}
            class="w-full px-3 py-2 text-left text-xs text-red-400 hover:bg-red-500/10 transition-colors"
          >
            Remove from group
          </button>
        <% end %>

        <%!-- Moderation (Not self) --%>
        <%= unless @is_self do %>
          <button
            phx-click="report_user"
            phx-value-user_id={@member.user_id}
            data-confirm={"Report @#{@member.user.username} for abusive behavior?"}
            class="w-full px-3 py-2 text-left text-xs text-yellow-400/80 hover:bg-yellow-500/10 transition-colors border-t border-white/5"
          >
            Report User
          </button>
          
          <button
            phx-click="block_user"
            phx-value-user_id={@member.user_id}
            data-confirm={"Block @#{@member.user.username}? You won't see their messages anymore."}
            class="w-full px-3 py-2 text-left text-xs text-red-400 hover:bg-red-500/10 transition-colors"
          >
            Block User
          </button>
        <% end %>

        <%= if @is_self do %>
          <button
            phx-click="leave_room"
            data-confirm="Leave this group?"
            class="w-full px-3 py-2 text-left text-xs text-red-400 hover:bg-red-500/10 transition-colors"
          >
            Leave group
          </button>
        <% end %>
      </div>
    </div>
    """
  end

  # ============================================================================
  # UNIFIED INPUT BAR
  # One input for everything: chat, photo, voice
  # ============================================================================

  attr :room, :map, required: true
  attr :uploads, :map, default: nil
  attr :uploading, :boolean, default: false
  attr :recording_voice, :boolean, default: false
  attr :new_chat_message, :string, default: ""
  attr :chat_expanded, :boolean, default: false
  attr :show_chat, :boolean, default: true
  attr :show_add_menu, :boolean, default: false

  def unified_input_bar(assigns) do
    ~H"""
    <div class="fixed bottom-16 left-0 right-0 z-50 px-4 py-3 bg-gradient-to-t from-black via-black/95 to-transparent">
      <div class="max-w-lg mx-auto">
        <div
          id="unified-input-area"
          class="flex items-center gap-2 p-2 relative"
          phx-hook="RoomChatEncryption"
          data-room-code={@room.code}
        >
          <%!-- Chat toggle button (shows when chat is hidden) --%>
          <%= if not @show_chat do %>
            <button
              type="button"
              phx-click="toggle_chat_visibility"
              class="w-9 h-9 rounded-full flex items-center justify-center text-blue-400 hover:text-blue-300 hover:bg-blue-500/10 transition-colors cursor-pointer animate-pulse"
              title="Show chat"
            >
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z" />
              </svg>
            </button>
          <% end %>

          <%!-- Unified Add Button (+) with Menu --%>
          <div class="relative">
            <%!-- Plus Button --%>
            <button
              type="button"
              phx-click="toggle_add_menu"
              class="w-9 h-9 rounded-full flex items-center justify-center text-white/40 hover:text-white hover:bg-white/10 transition-colors cursor-pointer"
              title="Add content"
            >
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M12 4v16m8-8H4" />
              </svg>
            </button>

            <%!-- Add Menu --%>
            <%= if @show_add_menu do %>
              <div class="absolute bottom-full left-0 mb-2 w-32 bg-neutral-900/95 backdrop-blur-xl border border-white/10 rounded-xl shadow-2xl overflow-hidden animate-in fade-in zoom-in-95 duration-150">
                <%!-- Photo option --%>
                <button
                  type="button"
                  phx-click="trigger_photo_upload"
                  class="w-full flex items-center gap-3 px-4 py-3 hover:bg-white/10 transition-colors cursor-pointer border-b border-white/5"
                >
                  <svg class="w-4 h-4 text-white/70" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
                  </svg>
                  <span class="text-sm text-white/90">Photo</span>
                </button>

                <%!-- Note option --%>
                <button
                  type="button"
                  phx-click="open_note_modal"
                  class="w-full flex items-center gap-3 px-4 py-3 hover:bg-white/10 transition-colors cursor-pointer"
                >
                  <svg class="w-4 h-4 text-white/70" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                  </svg>
                  <span class="text-sm text-white/90">Note</span>
                </button>
              </div>

              <%!-- Backdrop to close menu --%>
              <div
                class="fixed inset-0 -z-10"
                phx-click="close_add_menu"
              ></div>
            <% end %>
          </div>

          <%!-- Text input --%>
          <div id={"unified-input-ignore-v3-#{@room.id}"} phx-update="ignore" class="flex-1 py-2">
            <input
              type="text"
              id="unified-message-input"
              value={@new_chat_message}
              placeholder="Message"
              style="font-size: 16px;"
              class="w-full bg-transparent text-white placeholder-white/40 focus:outline-none"
              autocomplete="off"
            />
          </div>

          <%!-- Voice button (record message) --%>
          <button
            type="button"
            id="fluid-voice-btn"
            phx-hook="RoomVoiceRecorder"
            data-room-id={@room.id}
            class={"w-9 h-9 rounded-full flex items-center justify-center transition-colors cursor-pointer #{if @recording_voice, do: "bg-red-500 text-white animate-pulse", else: "text-white/40 hover:text-white hover:bg-white/10"}"}
            title="Record voice message"
          >
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z" />
            </svg>
          </button>

          <%!-- Action buttons (walkie + send) - JS controlled, ignore LiveView updates --%>
          <div id={"action-buttons-ignore-#{@room.id}"} phx-update="ignore" class="flex items-center gap-2">
            <%!-- Walkie-Talkie button (hold to talk) --%>
            <div
              id="walkie-talkie-container"
              class="relative"
            >
              <button
                type="button"
                class="walkie-talk-btn w-9 h-9 rounded-full flex items-center justify-center transition-all cursor-pointer text-purple-400/60 hover:text-purple-300 hover:bg-purple-500/20 active:bg-purple-500/40 active:scale-110"
                title="Hold to talk (walkie-talkie)"
              >
                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5.636 18.364a9 9 0 010-12.728m12.728 0a9 9 0 010 12.728m-9.9-2.829a5 5 0 010-7.07m7.072 0a5 5 0 010 7.07M13 12a1 1 0 11-2 0 1 1 0 012 0z" />
                </svg>
              </button>
              <%!-- Indicator when someone is talking --%>
              <div class="walkie-indicator hidden absolute -top-8 left-1/2 -translate-x-1/2 whitespace-nowrap text-[10px] text-purple-300 bg-purple-900/80 px-2 py-1 rounded-full"></div>
            </div>

            <%!-- Send button (submit form) --%>
            <button
              type="button"
              id="send-unified-message-btn"
              class="w-9 h-9 rounded-full flex items-center justify-center transition-all cursor-pointer bg-white/10 text-white/40 scale-90"
              style="display: none;"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M5 12h14M12 5l7 7-7 7" />
              </svg>
            </button>
          </div>
        </div>

        <%!-- Upload progress --%>
        <%= if @uploading do %>
          <div class="mt-2 h-1 bg-white/10 rounded-full overflow-hidden">
            <div class="h-full bg-blue-500 animate-pulse" style="width: 50%"></div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # ============================================================================
  # ACCESS DENIED STATE
  # Shown when user doesn't have access to a private room
  # ============================================================================

  attr :room_access_denied, :boolean, default: false
  attr :room, :map, required: true
  attr :current_user, :map, default: nil

  def access_denied(assigns) do
    ~H"""
    <%= if @room_access_denied do %>
      <div class="text-center py-20">
        <p class="text-4xl mb-4">🔒</p>

        <p class="text-white/50 text-sm font-medium">private room</p>

        <p class="text-white/30 text-xs mt-2">you don't have access to this room</p>

        <%= if is_nil(@current_user) do %>
          <a
            href={"/auth?join=#{@room.code}"}
            class="inline-block mt-4 px-4 py-2 bg-emerald-500 text-black text-sm font-medium rounded-lg hover:bg-emerald-400 transition-colors"
          >
            sign in to join
          </a>
        <% else %>
          <p class="text-neutral-700 text-xs mt-4">ask the owner to invite you</p>
        <% end %>
      </div>
    <% end %>
    """
  end
end
