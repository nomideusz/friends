defmodule FriendsWeb.HomeLive.Components.FluidRoomComponents do
  @moduledoc """
  Fluid design components for private rooms.
  Content-first, contextual chat, minimal chrome.
  """
  use FriendsWeb, :html
  import FriendsWeb.HomeLive.Helpers

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
  # INLINE CHAT PANEL
  # Fixed at bottom, content visible above, expandable
  # ============================================================================

  attr :room, :map, required: true
  attr :room_messages, :list, default: []
  attr :current_user, :map, required: true
  attr :new_chat_message, :string, default: ""
  attr :typing_users, :map, default: %{}
  attr :expanded, :boolean, default: false
  attr :uploading, :boolean, default: false

  def inline_chat_panel(assigns) do
    has_typing = map_size(assigns.typing_users) > 0
    message_count = length(assigns.room_messages)
    assigns = assigns
      |> assign(:has_typing, has_typing)
      |> assign(:message_count, message_count)

    ~H"""
    <div class={"fixed bottom-0 inset-x-0 z-[150] transition-all duration-300 flex justify-center #{if @expanded, do: "h-[50vh]", else: "h-auto"}"}>
      <%!-- Glassmorphic container with enhanced design --%>
      <div class="h-full w-full max-w-3xl bg-neutral-900/95 backdrop-blur-xl backdrop-saturate-150 border-t border-x border-white/10 rounded-t-2xl sm:rounded-t-3xl flex flex-col shadow-[0_-4px_20px_rgba(0,0,0,0.3)]">
        
        <%!-- Expand/Collapse Handle --%>
        <button
          type="button"
          phx-click="toggle_chat_expanded"
          class="w-full py-2 flex justify-center cursor-pointer hover:bg-white/5 transition-colors"
        >
          <div class="flex items-center gap-2">
            <div class="w-8 h-1 rounded-full bg-white/20"></div>
            <%= if @message_count > 0 do %>
              <span class="text-[10px] text-white/40">{@message_count} messages</span>
            <% end %>
          </div>
        </button>

        <%!-- Messages Area (visible when expanded) --%>
        <%= if @expanded do %>
          <div
            id="inline-chat-messages"
            class="flex-1 overflow-y-auto scrollbar-hide px-4 pb-2 space-y-2"
            phx-hook="RoomChatScroll"
            data-room-id={@room.id}
          >
            <%= if @room_messages == [] do %>
              <div class="flex items-center justify-center py-8 text-white/30 text-sm">
                No messages yet
              </div>
            <% else %>
              <%= for message <- @room_messages do %>
                <div class={"flex flex-col gap-0.5 #{if message.sender_id == @current_user.id, do: "items-end", else: "items-start"}"}>
                  <%= if message.sender_id != @current_user.id do %>
                    <span class="text-[10px] text-white/30 ml-1">@{message.sender.username}</span>
                  <% end %>

                  <div class={"group relative max-w-[85%] px-3 py-2 rounded-2xl #{if message.sender_id == @current_user.id, do: "bg-blue-500/20 rounded-tr-sm", else: "bg-white/5 rounded-tl-sm"}"}>
                    <%!-- Smart Timestamp (Hover) --%>
                    <span class={"absolute top-1/2 -translate-y-1/2 text-[10px] text-white/40 opacity-0 group-hover:opacity-100 transition-opacity duration-200 whitespace-nowrap pointer-events-none #{if message.sender_id == @current_user.id, do: "right-full mr-2", else: "left-full ml-2"}"}>
                      {Calendar.strftime(message.inserted_at, "%I:%M %p")}
                    </span>

                    <%= if message.content_type == "voice" do %>
                      <%!-- Voice message --%>
                      <div
                        class="flex items-center gap-3 min-w-[180px]"
                        id={"inline-voice-#{message.id}"}
                        phx-hook="RoomVoicePlayer"
                        data-message-id={message.id}
                        data-room-id={@room.id}
                      >
                        <button class="room-voice-play-btn w-8 h-8 rounded-full bg-white/10 flex items-center justify-center text-white cursor-pointer hover:bg-white/20 transition-all">
                          <svg class="w-3 h-3 ml-0.5" fill="currentColor" viewBox="0 0 24 24">
                            <path d="M8 5v14l11-7z" />
                          </svg>
                        </button>
                        <div class="flex-1 flex items-center gap-[2px] h-5 room-voice-waveform">
                          <% heights = [30, 50, 70, 90, 60, 85, 45, 95, 55, 75] %>
                          <%= for height <- heights do %>
                            <div class="room-voice-bar w-[2px] rounded-full bg-white/30" style={"height: #{height}%;"}></div>
                          <% end %>
                        </div>
                        <% metadata = message.metadata || %{} %>
                        <% duration_ms = Map.get(metadata, "duration_ms") || Map.get(metadata, :duration_ms) || 0 %>
                        <span class="text-[10px] text-white/50 room-voice-time">
                          {div(duration_ms, 60000)}:{rem(div(duration_ms, 1000), 60) |> Integer.to_string() |> String.pad_leading(2, "0")}
                        </span>
                        <%= if message.nonce do %>
                          <span class="hidden room-voice-data" data-encrypted={Base.encode64(message.encrypted_content)} data-nonce={Base.encode64(message.nonce)}></span>
                        <% end %>
                      </div>
                    <% else %>
                      <%!-- Text message --%>
                      <%= if message.nonce do %>
                        <p
                          class="text-sm text-white/90 room-decrypted-content"
                          id={"inline-msg-#{message.id}"}
                          data-encrypted-content={Base.encode64(message.encrypted_content)}
                          data-nonce={Base.encode64(message.nonce)}
                        >
                          <span class="text-white/30">...</span>
                        </p>
                      <% else %>
                        <p class="text-sm text-white/90">{message.encrypted_content}</p>
                      <% end %>
                    <% end %>
                  </div>
                </div>
              <% end %>
            <% end %>

            <%!-- Typing indicators --%>
            <%= for {user_id, typing_info} <- @typing_users do %>
              <div class="flex flex-col items-start animate-in fade-in duration-200" id={"typing-inline-#{user_id}"}>
                <span class="text-[10px] text-white/30 mb-1 ml-1">@{typing_info.username}</span>
                <div class="max-w-[85%] px-3 py-2 rounded-2xl bg-white/5 rounded-tl-sm border border-white/10">
                  <p class="text-sm text-white/30">
                    {typing_info.text}<span class="animate-pulse text-white/20">│</span>
                  </p>
                </div>
              </div>
            <% end %>
          </div>
        <% else %>
          <%!-- Compact preview (when collapsed) --%>
          <% active_typer = Enum.at(Enum.to_list(@typing_users), 0) %>
          
          <%= if active_typer do %>
            <% {_user_id, typing_info} = active_typer %>
            <div class="px-4 pb-2">
              <div class="flex items-center gap-2 text-sm text-white/50 truncate animate-pulse">
                <span class="text-white/30">@{typing_info.username}:</span>
                <span class="truncate text-white/50">
                  {typing_info.text}<span class="animate-pulse text-white/20">│</span>
                </span>
              </div>
            </div>
          <% else %>
            <%= if @message_count > 0 do %>
              <% last_msg = List.last(@room_messages) %>
              <div class="px-4 pb-2">
                <div class="flex items-center gap-2 text-sm text-white/50 truncate">
                  <span class="text-white/30">@{last_msg.sender.username}:</span>
                  <span class="truncate">
                    <%= if last_msg.content_type == "voice" do %>
                      🎤 Voice message
                    <% else %>
                      <%= if last_msg.nonce do %>
                        <span
                          id={"msg-preview-#{last_msg.id}"}
                          phx-hook="DecryptedPreview"
                          data-room-id={@room.id}
                          data-encrypted-content={Base.encode64(last_msg.encrypted_content)}
                          data-nonce={Base.encode64(last_msg.nonce)}
                          class="truncate text-white/30"
                        >...</span>
                      <% else %>
                        <span class="truncate">{last_msg.encrypted_content}</span>
                      <% end %>
                    <% end %>
                  </span>
                </div>
              </div>
            <% end %>
          <% end %>
        <% end %>

        <%!-- Upload Progress --%>
        <%= if @uploading do %>
          <div class="px-4 pb-2">
            <div class="h-1 bg-white/10 rounded-full overflow-hidden">
              <div class="h-full bg-blue-500 animate-pulse transition-all" style="width: 60%;"></div>
            </div>
          </div>
        <% end %>

        <%!-- Input Area with Actions --%>
        <div class="px-4 pb-4 pt-2">
          <div
            id="inline-chat-input-area"
            phx-hook="InlineChatInput"
            data-room-id={@room.id}
            class="flex items-center gap-2"
          >
            <%!-- Action Menu Toggle --%>
            <div class="relative">
              <button
                type="button"
                class="action-toggle w-10 h-10 rounded-full flex items-center justify-center bg-white/10 border border-white/20 text-white/60 hover:bg-white/20 hover:text-white transition-all cursor-pointer"
                title="Add content"
              >
                <svg class="w-5 h-5 action-icon-plus" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
                </svg>
                <svg class="w-5 h-5 action-icon-close hidden" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
              
              <%!-- Action Menu (monochrome) --%>
              <div class="action-menu hidden absolute bottom-full left-0 mb-2 p-2 bg-neutral-800/95 backdrop-blur-xl border border-white/10 rounded-xl shadow-2xl" style="width: 160px;">
                <div class="grid grid-cols-2 gap-2">
                  <button type="button" class="action-photo flex flex-col items-center justify-center gap-1 p-3 rounded-lg hover:bg-white/10 transition-colors cursor-pointer" style="min-width: 68px;">
                    <svg class="w-5 h-5 text-white/70" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
                    </svg>
                    <span class="text-[10px] text-white/50">Photo</span>
                  </button>
                  <button type="button" class="action-note flex flex-col items-center justify-center gap-1 p-3 rounded-lg hover:bg-white/10 transition-colors cursor-pointer" style="min-width: 68px;">
                    <svg class="w-5 h-5 text-white/70" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                    </svg>
                    <span class="text-[10px] text-white/50">Note</span>
                  </button>
                  <button type="button" class="action-voice flex flex-col items-center justify-center gap-1 p-3 rounded-lg hover:bg-white/10 transition-colors cursor-pointer" style="min-width: 68px;">
                    <svg class="w-5 h-5 text-white/70" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z" />
                    </svg>
                    <span class="text-[10px] text-white/50">Voice</span>
                  </button>
                </div>
              </div>

            </div>
            
            <%!-- Text Input --%>
            <div id={"chat-input-ignore-#{@room.id}"} phx-update="ignore" class="flex-1">
              <input
                type="text"
                name="message"
                value={@new_chat_message}
                phx-change="update_chat_input"
                phx-debounce="1000"
                placeholder="Message..."
                autocomplete="off"
                style="font-size: 16px;"
                class="chat-input w-full bg-white/5 border border-white/10 rounded-xl px-4 py-3 text-white placeholder-white/30 focus:border-white/20 focus:outline-none"
              />
            </div>
            
            <%!-- Walkie-Talkie Button (hold to talk) --%>
            <%!-- Morphing Send / Walkie Button --%>
            <div id="chat-button-container" phx-update="ignore" class="relative w-10 h-10 flex items-center justify-center transition-all">
              <%!-- Walkie-Talkie Button (Visible when empty) --%>
              <button
                type="button"
                class={"walkie-btn absolute inset-0 w-10 h-10 rounded-full flex items-center justify-center bg-white/10 border border-white/20 text-white/60 hover:bg-emerald-500/30 hover:border-emerald-500/50 hover:text-emerald-400 cursor-pointer active:bg-emerald-500 active:text-white active:scale-110 transition-all duration-200 ease-out #{if @new_chat_message != "", do: "opacity-0 scale-50 pointer-events-none", else: "opacity-100 scale-100"}"}
                title="Hold to talk"
              >
                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5.636 18.364a9 9 0 010-12.728m12.728 0a9 9 0 010 12.728m-9.9-2.829a5 5 0 010-7.07m7.072 0a5 5 0 010 7.07M13 12a1 1 0 11-2 0 1 1 0 012 0z" />
                </svg>
              </button>
              
              <%!-- Send Button (Visible when typing) --%>
              <button
                type="button"
                class={"send-btn absolute inset-0 w-10 h-10 rounded-full flex items-center justify-center bg-white text-black cursor-pointer transition-all duration-200 ease-out #{if @new_chat_message != "", do: "opacity-100 scale-100 rotate-0", else: "opacity-0 scale-50 -rotate-90 pointer-events-none"}"}
              >
                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M5 12h14M12 5l7 7-7 7" />
                </svg>
              </button>
            </div>
          </div>
        </div>
      </div>
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
  # EMPTY STATE
  # Just a subtle orb, no text
  # ============================================================================

  def fluid_empty_state(assigns) do
    ~H"""
    <div class="flex items-center justify-center h-[60vh]">
      <div class="w-16 h-16 rounded-full bg-white/5 border border-white/10 flex items-center justify-center animate-pulse">
        <div class="w-3 h-3 rounded-full bg-white/20"></div>
      </div>
    </div>
    """
  end

  # ============================================================================
  # CONTENT GRID
  # Full-width masonry-style grid
  # ============================================================================

  attr :items, :list, required: true
  attr :room, :map, required: true
  attr :current_user, :map, required: true

  def fluid_content_grid(assigns) do
    # Check if current user is admin
    is_admin = Friends.Social.is_admin?(assigns.current_user)
    assigns = assign(assigns, :is_admin, is_admin)

    ~H"""
    <div
      id="fluid-items-grid"
      phx-update="stream"
      class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-1 p-1"
    >
      <%= for {dom_id, item} <- @items do %>
        <%!-- Skip audio items - they appear in the chat stream instead --%>
        <%= unless Map.get(item, :content_type) == "audio/encrypted" do %>
          <.fluid_content_item id={dom_id} item={item} room={@room} current_user={@current_user} is_admin={@is_admin} />
        <% end %>
      <% end %>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :item, :map, required: true
  attr :room, :map, required: true
  attr :current_user, :map, required: true
  attr :is_admin, :boolean, default: false

  def fluid_content_item(assigns) do
    ~H"""
    <%= case Map.get(@item, :type) do %>
      <% :gallery -> %>
        <div
          id={@id}
          class="aspect-square relative overflow-hidden cursor-pointer group"
          phx-click="view_gallery"
          phx-value-batch_id={@item.batch_id}
        >
          <img
            src={get_in(@item, [:first_photo, :thumbnail_data]) || get_in(@item, [:first_photo, :image_data])}
            alt=""
            class="w-full h-full object-cover"
            loading="lazy"
          />
          <%!-- Gallery badge --%>
          <div class="absolute top-2 right-2 flex items-center gap-1 px-2 py-1 rounded-lg bg-black/70 backdrop-blur-md border border-white/20 shadow-lg">
            <svg class="w-3.5 h-3.5 text-white/80" fill="currentColor" viewBox="0 0 24 24">
              <path d="M4 6H2v14c0 1.1.9 2 2 2h14v-2H4V6zm16-4H8c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm0 14H8V4h12v12z"/>
            </svg>
            <span class="text-xs font-semibold text-white">{@item.photo_count}</span>
          </div>
          <%!-- Hover overlay --%>
          <div class="absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100 transition-opacity"></div>
        </div>

      <% :photo -> %>
        <%= if Map.get(@item, :content_type) == "audio/encrypted" do %>
          <%!-- Voice Note (Fluid Design) --%>
          <div
            id={@id}
            class="aspect-square relative overflow-hidden bg-gradient-to-br from-purple-900/40 via-neutral-900 to-blue-900/40 flex flex-col items-center justify-center group"
            phx-hook="GridVoicePlayer"
            data-item-id={@item.id}
            data-room-id={@room.id}
          >
            <%!-- Ambient glow background --%>
            <div class="absolute inset-0 opacity-30">
              <div class="absolute top-1/4 left-1/4 w-24 h-24 rounded-full bg-purple-500/30 blur-2xl"></div>
              <div class="absolute bottom-1/4 right-1/4 w-20 h-20 rounded-full bg-blue-500/30 blur-2xl"></div>
            </div>
            
            <%!-- Hidden data element --%>
            <div class="hidden" id={"grid-voice-data-#{@item.id}"} data-encrypted={@item.image_data} data-nonce={@item.thumbnail_data}></div>
            
            <%!-- Waveform visualization bars --%>
            <div class="flex items-center gap-[3px] h-12 mb-4 z-10">
              <% heights = [35, 55, 75, 45, 85, 60, 90, 50, 70, 40, 80, 55, 65, 85, 45] %>
              <%= for height <- heights do %>
                <div 
                  class="w-[4px] rounded-full bg-gradient-to-t from-purple-400/60 to-blue-400/60 transition-all duration-300"
                  style={"height: #{height}%;"}
                ></div>
              <% end %>
            </div>
            
            <%!-- Play button with glow effect --%>
            <button class="grid-voice-play-btn relative w-14 h-14 rounded-full bg-white/10 backdrop-blur-md border border-white/20 flex items-center justify-center text-white hover:bg-white/20 hover:scale-105 transition-all cursor-pointer group-hover:shadow-[0_0_20px_rgba(168,85,247,0.4)] z-10">
              <svg class="w-6 h-6 ml-0.5" fill="currentColor" viewBox="0 0 24 24">
                <path d="M8 5v14l11-7z" />
              </svg>
            </button>
            <%!-- Delete button for owner or admin --%>
            <%= if @item.user_id == "user-#{@current_user.id}" or @item.user_id == @current_user.id or @is_admin do %>
              <button
                type="button"
                phx-click="delete_photo"
                phx-value-id={@item.id}
                data-confirm="Delete this voice message?"
                class="absolute top-2 right-2 w-6 h-6 rounded-full bg-black/60 text-white/70 hover:text-red-400 opacity-0 group-hover:opacity-100 transition-all cursor-pointer flex items-center justify-center z-20"
              >
                <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            <% end %>
          </div>
        <% else %>
          <%!-- Photo --%>
          <div
            id={@id}
            class="aspect-square relative overflow-hidden cursor-pointer group"
            phx-click="view_full_image"
            phx-value-photo_id={@item.id}
          >
            <%= if @item.thumbnail_data do %>
              <img
                src={@item.thumbnail_data}
                alt=""
                class="w-full h-full object-cover"
                loading="lazy"
              />
            <% else %>
              <div class="w-full h-full bg-neutral-800 animate-pulse"></div>
            <% end %>
            <%!-- Hover overlay --%>
            <div class="absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100 transition-opacity"></div>

            <%!-- Delete button (owner or admin) --%>
            <% is_owner = @item.user_id == "user-#{@current_user.id}" or @item.user_id == @current_user.id %>
            <%= if is_owner or @is_admin do %>
              <button
                type="button"
                phx-click="delete_photo"
                phx-value-id={@item.id}
                data-confirm="Delete?"
                class="absolute top-2 right-2 w-6 h-6 rounded-full bg-black/60 text-white/70 hover:text-red-400 opacity-0 group-hover:opacity-100 transition-all cursor-pointer flex items-center justify-center z-10"
              >
                <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            <% end %>
            
            <%!-- Pin button (owner only) --%>
            <%= if @room.owner_id == @current_user.id do %>
              <button
                type="button"
                phx-click={if Map.get(@item, :pinned_at), do: "unpin_item", else: "pin_item"}
                phx-value-type="photo"
                phx-value-id={@item.id}
                class="absolute top-2 left-2 w-6 h-6 rounded-full bg-black/60 flex items-center justify-center cursor-pointer opacity-0 group-hover:opacity-100 transition-all z-10"
                title={if Map.get(@item, :pinned_at), do: "Unpin", else: "Pin"}
              >
                <svg class={"w-3 h-3 #{if Map.get(@item, :pinned_at), do: "text-yellow-400", else: "text-white/70 hover:text-yellow-400"}"} fill={if Map.get(@item, :pinned_at), do: "currentColor", else: "none"} stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 5a2 2 0 012-2h10a2 2 0 012 2v16l-7-3.5L5 21V5z" />
                </svg>
              </button>
            <% end %>
            
            <%!-- Pinned indicator (always visible for non-owners) --%>
            <%= if Map.get(@item, :pinned_at) && @room.owner_id != @current_user.id do %>
              <div class="absolute top-2 left-2 w-5 h-5 rounded-full bg-yellow-500 flex items-center justify-center shadow-lg z-10" title="Pinned">
                <svg class="w-2.5 h-2.5 text-black" fill="currentColor" viewBox="0 0 24 24">
                  <path d="M5 5a2 2 0 012-2h10a2 2 0 012 2v16l-7-3.5L5 21V5z" />
                </svg>
              </div>
            <% end %>
          </div>
        <% end %>

      <% :note -> %>
        <%!-- Note --%>
        <div
          id={@id}
          class="aspect-square relative overflow-hidden bg-neutral-900/50 border border-white/5 cursor-pointer group p-4 flex flex-col"
          phx-click="view_full_note"
          phx-value-id={@item.id}
          phx-value-content={@item.content}
          phx-value-user={@item.user_name}
          phx-value-time={format_time(@item.inserted_at)}
        >
          <p class="text-sm text-white/80 line-clamp-5 flex-1">{@item.content}</p>
          <div class="mt-2 flex items-center gap-2">
            <div class="w-4 h-4 rounded-full" style={"background-color: #{@item.user_color || "#888"}"}></div>
            <span class="text-[10px] text-white/40">@{@item.user_name}</span>
          </div>

          <%!-- Delete button (owner or admin) --%>
          <% is_owner = @item.user_id == "user-#{@current_user.id}" or @item.user_id == @current_user.id %>
          <%= if is_owner or @is_admin do %>
            <button
              type="button"
              phx-click="delete_note"
              phx-value-id={@item.id}
              data-confirm="Delete?"
              phx-click-stop
              class="absolute top-2 right-2 w-6 h-6 rounded-full bg-black/60 text-white/70 hover:text-red-400 opacity-0 group-hover:opacity-100 transition-all cursor-pointer flex items-center justify-center z-10"
            >
              <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          <% end %>
          
          <%!-- Pin button (owner only) --%>
          <%= if @room.owner_id == @current_user.id do %>
            <button
              type="button"
              phx-click={if Map.get(@item, :pinned_at), do: "unpin_item", else: "pin_item"}
              phx-value-type="note"
              phx-value-id={@item.id}
              class="absolute top-2 left-2 w-6 h-6 rounded-full bg-black/60 flex items-center justify-center cursor-pointer opacity-0 group-hover:opacity-100 transition-all z-10"
              title={if Map.get(@item, :pinned_at), do: "Unpin", else: "Pin"}
            >
              <svg class={"w-3 h-3 #{if Map.get(@item, :pinned_at), do: "text-yellow-400", else: "text-white/70 hover:text-yellow-400"}"} fill={if Map.get(@item, :pinned_at), do: "currentColor", else: "none"} stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 5a2 2 0 012-2h10a2 2 0 012 2v16l-7-3.5L5 21V5z" />
              </svg>
            </button>
          <% end %>
          
          <%!-- Pinned indicator (always visible for non-owners) --%>
          <%= if Map.get(@item, :pinned_at) && @room.owner_id != @current_user.id do %>
            <div class="absolute top-2 left-2 w-5 h-5 rounded-full bg-yellow-500 flex items-center justify-center shadow-lg z-10" title="Pinned">
              <svg class="w-2.5 h-2.5 text-black" fill="currentColor" viewBox="0 0 24 24">
                <path d="M5 5a2 2 0 012-2h10a2 2 0 012 2v16l-7-3.5L5 21V5z" />
              </svg>
            </div>
          <% end %>
        </div>

      <% _ -> %>
        <div id={@id} class="aspect-square bg-neutral-900"></div>
    <% end %>
    """
  end

  # ============================================================================
  # FLUID CHAT OVERLAY
  # Appears above input when messages exist, grows fluidly
  # ============================================================================

  attr :room, :map, required: true
  attr :room_messages, :list, default: []
  attr :current_user, :map, required: true
  attr :new_chat_message, :string, default: ""
  attr :chat_expanded, :boolean, default: false
  attr :typing_users, :map, default: %{}
  attr :show_chat, :boolean, default: true

  def fluid_chat_overlay(assigns) do
    has_messages = length(assigns.room_messages) > 0
    has_typing = map_size(assigns.typing_users) > 0
    assigns = assign(assigns, :has_messages, has_messages)
    assigns = assign(assigns, :has_typing, has_typing)

    ~H"""
    <%= if @show_chat && (@has_messages or @chat_expanded or @has_typing) do %>
      <div
        id="fluid-chat-overlay"
        class="fixed bottom-36 left-0 right-0 z-40 pointer-events-none"
      >
        <%!-- Invisible backdrop to close chat when clicking outside --%>
        <div
          class="fixed inset-0 z-[-1] pointer-events-auto"
          phx-click="toggle_chat_visibility"
        ></div>
        <div class="max-w-lg mx-auto px-4 pointer-events-auto">
          <%!-- Chat container with glass effect --%>
          <div class="bg-black/80 backdrop-blur-xl border border-white/10 rounded-2xl overflow-hidden shadow-2xl animate-in slide-in-from-bottom-4 duration-300">
            <%!-- Header with collapse handle and hide button --%>
            <div class="flex items-center justify-between px-3">
              <button
                phx-click="toggle_chat_visibility"
                class="p-2 text-white/40 hover:text-white/70 transition-colors cursor-pointer"
                title="Hide chat"
              >
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
              <button
                phx-click="toggle_chat_expanded"
                class="flex-1 py-2 flex justify-center cursor-pointer hover:bg-white/5 transition-colors"
              >
                <div class="w-8 h-1 rounded-full bg-white/20"></div>
              </button>
              <div class="w-8"></div> <%!-- Spacer for balance --%>
            </div>

            <%!-- Messages (scrollable container) --%>
            <div
              id="chat-messages-scroll"
              class="max-h-[40vh] overflow-y-auto px-4 pb-4 space-y-3"
              phx-hook="RoomChatScroll"
              data-room-id={@room.id}
            >
              <%= for message <- @room_messages do %>
                <div class={"flex flex-col gap-0.5 #{if message.sender_id == @current_user.id, do: "items-end", else: "items-start"}"}>
                  <%= if message.sender_id != @current_user.id do %>
                    <button
                      type="button"
                      phx-click="open_dm"
                      phx-value-user_id={message.sender_id}
                      class="text-[10px] text-white/30 hover:text-white/60 mb-1 ml-1 cursor-pointer transition-colors"
                    >@{message.sender.username}</button>
                  <% end %>

                  <div class={"max-w-[85%] px-3 py-2 rounded-2xl #{if message.sender_id == @current_user.id, do: "bg-white/10 rounded-tr-sm", else: "bg-white/5 rounded-tl-sm"}"}>
                    <%= if message.content_type == "voice" do %>
                      <%!-- Voice message with waveform (Fluid Design) --%>
                      <div
                        class="flex items-center gap-3 min-w-[220px] py-1"
                        id={"chat-voice-#{message.id}"}
                        phx-hook="RoomVoicePlayer"
                        data-message-id={message.id}
                        data-room-id={@room.id}
                      >
                        <%!-- Play button with gradient and glow --%>
                        <button class={"room-voice-play-btn w-10 h-10 rounded-full backdrop-blur-md flex items-center justify-center text-white cursor-pointer transition-all flex-shrink-0 hover:scale-110 #{if message.sender_id == @current_user.id, do: "bg-gradient-to-br from-blue-500/40 to-purple-500/40 border border-blue-400/30 hover:shadow-[0_0_15px_rgba(59,130,246,0.4)]", else: "bg-gradient-to-br from-purple-500/40 to-pink-500/40 border border-purple-400/30 hover:shadow-[0_0_15px_rgba(168,85,247,0.4)]"}"}>
                          <svg class="w-4 h-4 ml-0.5" fill="currentColor" viewBox="0 0 24 24">
                            <path d="M8 5v14l11-7z" />
                          </svg>
                        </button>
                        <%!-- Waveform bars with gradient colors --%>
                        <div class="flex-1 flex items-center gap-[2px] h-8 room-voice-waveform">
                          <% heights = [30, 50, 70, 90, 60, 85, 45, 95, 55, 75, 40, 80, 60, 90, 35, 65, 85, 50, 70, 40] %>
                          <%= for height <- heights do %>
                            <div
                              class={"room-voice-bar w-[3px] rounded-full transition-all duration-150 #{if message.sender_id == @current_user.id, do: "bg-gradient-to-t from-blue-400/50 to-cyan-400/50", else: "bg-gradient-to-t from-purple-400/50 to-pink-400/50"}"}
                              style={"height: #{height}%;"}
                            ></div>
                          <% end %>
                        </div>
                        <%!-- Duration with subtle styling --%>
                        <span class="text-[10px] text-white/50 room-voice-time flex-shrink-0 font-medium">
                          <% metadata = message.metadata || %{} %>
                          <% duration_ms = Map.get(metadata, "duration_ms") || Map.get(metadata, :duration_ms) || 0 %>
                          {div(duration_ms, 60000)}:{rem(div(duration_ms, 1000), 60) |> Integer.to_string() |> String.pad_leading(2, "0")}
                        </span>
                        <span class="hidden room-voice-data" data-encrypted={Base.encode64(message.encrypted_content)} data-nonce={Base.encode64(message.nonce)}></span>
                      </div>
                    <% else %>
                      <%!-- Text message --%>
                      <p
                        class="text-sm text-white/90 room-decrypted-content"
                        id={"chat-msg-#{message.id}"}
                        data-encrypted={Base.encode64(message.encrypted_content)}
                        data-nonce={Base.encode64(message.nonce)}
                      >
                        <span class="text-white/30">...</span>
                      </p>
                    <% end %>
                  </div>

                  <%!-- Timestamp --%>
                  <span class={"text-[9px] text-white/20 #{if message.sender_id == @current_user.id, do: "mr-2", else: "ml-2"}"}>
                    <.message_timestamp inserted_at={message.inserted_at} />
                  </span>
                </div>
              <% end %>

              <%!-- Live Typing Indicators (Ghost Messages) --%>
              <%= for {user_id, typing_info} <- @typing_users do %>
                <div class="flex flex-col items-start animate-in fade-in duration-200" id={"typing-#{user_id}"}>
                  <span class="text-[10px] text-white/30 mb-1 ml-1">@{typing_info.username}</span>
                  <div class="max-w-[85%] px-3 py-2 rounded-2xl bg-white/5 rounded-tl-sm border border-white/10">
                    <p class="text-sm text-white/30">
                      {typing_info.text}<span class="animate-pulse text-white/20">│</span>
                    </p>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    <% end %>
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
  # ============================================================================
  # CHAT SHEET
  # Full-screen chat overlay opened from toolbar
  # ============================================================================

  attr :show, :boolean, default: false
  attr :room, :map, required: true
  attr :room_messages, :list, default: []
  attr :current_user, :map, required: true
  attr :new_chat_message, :string, default: ""
  attr :typing_users, :map, default: %{}

  def chat_sheet(assigns) do
    has_typing = map_size(assigns.typing_users) > 0
    assigns = assign(assigns, :has_typing, has_typing)

    ~H"""
    <%= if @show do %>
      <div class="fixed inset-0 z-[200]" phx-window-keydown="toggle_chat_visibility" phx-key="escape">
        <%!-- Backdrop --%>
        <div
          class="absolute inset-0 bg-black/80 backdrop-blur-sm animate-in fade-in duration-200"
          phx-click="toggle_chat_visibility"
        ></div>

        <%!-- Sheet --%>
        <div class="absolute inset-x-0 bottom-0 z-10 flex justify-center animate-in slide-in-from-bottom duration-300">
          <div class="w-full max-w-lg bg-neutral-900/95 backdrop-blur-xl border-t border-x border-white/10 rounded-t-3xl shadow-2xl max-h-[85vh] flex flex-col">
            <%!-- Handle --%>
            <div class="py-3 flex justify-center cursor-pointer" phx-click="toggle_chat_visibility">
              <div class="w-10 h-1 rounded-full bg-white/20"></div>
            </div>

            <%!-- Messages --%>
            <div
              id="chat-sheet-messages"
              class="flex-1 overflow-y-auto px-4 pb-4 space-y-3"
              phx-hook="RoomChatScroll"
              data-room-id={@room.id}
            >
              <%= if @room_messages == [] do %>
                <div class="flex items-center justify-center py-12 text-white/30 text-sm">
                  No messages yet
                </div>
              <% else %>
                <%= for message <- @room_messages do %>
                  <div class={"flex flex-col gap-0.5 #{if message.sender_id == @current_user.id, do: "items-end", else: "items-start"}"}>
                    <%= if message.sender_id != @current_user.id do %>
                      <button
                        type="button"
                        phx-click="open_dm"
                        phx-value-user_id={message.sender_id}
                        class="text-[10px] text-white/30 hover:text-white/60 mb-1 ml-1 cursor-pointer transition-colors"
                      >@{message.sender.username}</button>
                    <% end %>

                    <div class={"max-w-[85%] px-3 py-2 rounded-2xl #{if message.sender_id == @current_user.id, do: "bg-blue-500/20 rounded-tr-sm", else: "bg-white/5 rounded-tl-sm"}"}>
                      <%= if message.content_type == "voice" do %>
                        <%!-- Voice message --%>
                        <div
                          class="flex items-center gap-3 min-w-[200px]"
                          id={"chat-sheet-voice-#{message.id}"}
                          phx-hook="RoomVoicePlayer"
                          data-message-id={message.id}
                          data-room-id={@room.id}
                        >
                          <button class="room-voice-play-btn w-9 h-9 rounded-full bg-white/10 flex items-center justify-center text-white cursor-pointer hover:bg-white/20 transition-all">
                            <svg class="w-4 h-4 ml-0.5" fill="currentColor" viewBox="0 0 24 24">
                              <path d="M8 5v14l11-7z" />
                            </svg>
                          </button>
                          <div class="flex-1 flex items-center gap-[2px] h-6 room-voice-waveform">
                            <% heights = [30, 50, 70, 90, 60, 85, 45, 95, 55, 75] %>
                            <%= for height <- heights do %>
                              <div class="room-voice-bar w-[3px] rounded-full bg-white/30" style={"height: #{height}%;"}></div>
                            <% end %>
                          </div>
                          <span class="text-[10px] text-white/50 room-voice-time">
                            <% metadata = message.metadata || %{} %>
                            <% duration_ms = Map.get(metadata, "duration_ms") || Map.get(metadata, :duration_ms) || 0 %>
                            {div(duration_ms, 60000)}:{rem(div(duration_ms, 1000), 60) |> Integer.to_string() |> String.pad_leading(2, "0")}
                          </span>
                          <%= if message.nonce do %>
                            <span class="hidden room-voice-data" data-encrypted={Base.encode64(message.encrypted_content)} data-nonce={Base.encode64(message.nonce)}></span>
                          <% end %>
                        </div>
                      <% else %>
                        <%!-- Text message --%>
                        <%= if message.nonce do %>
                          <%!-- Encrypted message - needs JS decryption --%>
                          <p
                            class="text-sm text-white/90 room-decrypted-content"
                            id={"chat-sheet-msg-#{message.id}"}
                            data-encrypted={Base.encode64(message.encrypted_content)}
                            data-nonce={Base.encode64(message.nonce)}
                          >
                            <span class="text-white/30">...</span>
                          </p>
                        <% else %>
                          <%!-- Plain text message - display directly --%>
                          <p class="text-sm text-white/90">
                            {message.encrypted_content}
                          </p>
                        <% end %>
                      <% end %>
                    </div>

                    <%!-- Timestamp --%>
                    <span class={"text-[9px] text-white/20 #{if message.sender_id == @current_user.id, do: "mr-2", else: "ml-2"}"}>
                      <.message_timestamp inserted_at={message.inserted_at} />
                    </span>
                  </div>
                <% end %>
              <% end %>

              <%!-- Typing indicators --%>
              <%= for {user_id, typing_info} <- @typing_users do %>
                <div class="flex flex-col items-start animate-in fade-in duration-200" id={"typing-sheet-#{user_id}"}>
                  <span class="text-[10px] text-white/30 mb-1 ml-1">@{typing_info.username}</span>
                  <div class="max-w-[85%] px-3 py-2 rounded-2xl bg-white/5 rounded-tl-sm border border-white/10">
                    <p class="text-sm text-white/30">
                      {typing_info.text}<span class="animate-pulse text-white/20">│</span>
                    </p>
                  </div>
                </div>
              <% end %>
            </div>

            <%!-- Input Area with Radial Action Menu --%>
            <div class="px-4 pb-4 pt-2 border-t border-white/5">
              <%!-- Radial Action Menu (appears above input when expanded) --%>
              <div
                id="chat-radial-menu"
                phx-hook="ChatRadialMenu"
                data-room-id={@room.id}
                class="relative"
              >
                <%!-- Radial Options Container (hidden by default) --%>
                <div class="radial-options hidden absolute bottom-full left-0 mb-3 pb-2">
                  <%!-- Radial backdrop --%>
                  <div class="radial-backdrop fixed inset-0 -z-10" data-action="close-radial"></div>
                  
                  <%!-- 2x2 Grid of options --%>
                  <div class="grid grid-cols-2 gap-2 p-2 bg-neutral-900/95 backdrop-blur-xl border border-white/10 rounded-2xl shadow-2xl animate-in fade-in zoom-in-95 duration-200">
                    <%!-- Photo Button --%>
                    <button
                      type="button"
                      class="radial-photo-btn w-16 h-16 rounded-xl flex flex-col items-center justify-center bg-gradient-to-br from-pink-500 to-rose-600 text-white shadow-lg shadow-pink-500/30 hover:scale-105 transition-transform cursor-pointer"
                      title="Share a photo"
                    >
                      <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
                      </svg>
                      <span class="text-[9px] mt-1 font-medium">Photo</span>
                    </button>
                    
                    <%!-- Note Button --%>
                    <button
                      type="button"
                      class="radial-note-btn w-16 h-16 rounded-xl flex flex-col items-center justify-center bg-gradient-to-br from-amber-500 to-orange-600 text-white shadow-lg shadow-amber-500/30 hover:scale-105 transition-transform cursor-pointer"
                      title="Write a note"
                    >
                      <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                      </svg>
                      <span class="text-[9px] mt-1 font-medium">Note</span>
                    </button>
                    
                    <%!-- Voice Note Button --%>
                    <button
                      type="button"
                      class="radial-voice-btn w-16 h-16 rounded-xl flex flex-col items-center justify-center bg-gradient-to-br from-purple-500 to-violet-600 text-white shadow-lg shadow-purple-500/30 hover:scale-105 transition-transform cursor-pointer"
                      title="Record voice message"
                    >
                      <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z" />
                      </svg>
                      <span class="text-[9px] mt-1 font-medium">Voice</span>
                    </button>
                    
                    <%!-- Walkie-Talkie Button --%>
                    <button
                      type="button"
                      class="radial-walkie-btn w-16 h-16 rounded-xl flex flex-col items-center justify-center bg-gradient-to-br from-emerald-500 to-teal-600 text-white shadow-lg shadow-emerald-500/30 hover:scale-105 transition-transform cursor-pointer"
                      title="Hold to talk (live)"
                    >
                      <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5.636 18.364a9 9 0 010-12.728m12.728 0a9 9 0 010 12.728m-9.9-2.829a5 5 0 010-7.07m7.072 0a5 5 0 010 7.07M13 12a1 1 0 11-2 0 1 1 0 012 0z" />
                      </svg>
                      <span class="text-[9px] mt-1 font-medium">Live</span>
                    </button>
                  </div>
                  
                  <%!-- Walkie indicator (shows who's talking) --%>
                  <div class="walkie-indicator hidden absolute -top-10 left-0 whitespace-nowrap text-[10px] text-emerald-300 bg-emerald-900/80 px-2 py-1 rounded-full"></div>
                </div>

                
                <%!-- Main Input Row --%>
                <form
                  id="chat-sheet-input-area"
                  class="flex items-center gap-2"
                  phx-submit="send_chat_message"
                  phx-change="update_chat_input"
                >
                  <%!-- Expand Actions Button (left side) --%>
                  <button
                    type="button"
                    class="radial-toggle w-10 h-10 rounded-full flex items-center justify-center bg-white/10 text-white/60 hover:bg-white/20 hover:text-white transition-all cursor-pointer shrink-0"
                    title="More actions"
                  >
                    <svg class="w-5 h-5 radial-icon-default" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
                    </svg>
                    <svg class="w-5 h-5 radial-icon-close hidden" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                    </svg>
                  </button>
                  
                  <%!-- Text Input (full width) --%>
                  <input
                    type="text"
                    name="message"
                    value={@new_chat_message}
                    phx-keyup="update_chat_message"
                    placeholder="Message..."
                    style="font-size: 16px; padding-left: 1rem;"
                    class="flex-1 bg-white/5 border border-white/10 rounded-xl py-3 text-white placeholder-white/30 focus:border-white/30 focus:outline-none"
                    id="chat-sheet-input"
                    autocomplete="off"
                    phx-hook="ChatInputFocus"
                  />
                  
                  <%!-- Send Button --%>
                  <button
                    type="submit"
                    id="chat-sheet-send-btn"
                    class={"w-10 h-10 rounded-full flex items-center justify-center transition-all cursor-pointer shrink-0 #{if @new_chat_message != "", do: "bg-blue-500 text-white", else: "bg-white/10 text-white/40"}"}
                  >
                    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M5 12h14M12 5l7 7-7 7" />
                    </svg>
                  </button>
                </form>
              </div>
            </div>

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

  # ============================================================================
  # MESSAGE TIMESTAMP
  # Shows relative or absolute timestamp for chat messages
  # ============================================================================

  attr :inserted_at, :any, required: true

  def message_timestamp(assigns) do
    now = DateTime.utc_now()

    # Convert NaiveDateTime to DateTime (assume UTC)
    inserted_at_utc = case assigns.inserted_at do
      %DateTime{} = dt -> dt
      %NaiveDateTime{} = ndt -> DateTime.from_naive!(ndt, "Etc/UTC")
    end

    diff_seconds = DateTime.diff(now, inserted_at_utc, :second)

    {text, _class} = cond do
      # Less than 1 minute - "Just now"
      diff_seconds < 60 ->
        {"Just now", "text-white/30"}

      # Less than 1 hour - "5m ago"
      diff_seconds < 3600 ->
        minutes = div(diff_seconds, 60)
        {"#{minutes}m", "text-white/25"}

      # Less than 24 hours - "2h ago"
      diff_seconds < 86400 ->
        hours = div(diff_seconds, 3600)
        {"#{hours}h", "text-white/20"}

      # Less than 7 days - "Monday 3:45 PM"
      diff_seconds < 604800 ->
        day_name = Calendar.strftime(assigns.inserted_at, "%a")
        time = Calendar.strftime(assigns.inserted_at, "%-I:%M %p") |> String.trim()
        {"#{day_name} #{time}", "text-white/20"}

      # Older - "Dec 25"
      true ->
        date = Calendar.strftime(assigns.inserted_at, "%b %d")
        {date, "text-white/15"}
    end

    assigns = assign(assigns, :text, text)

    ~H"""
    {text}
    """
  end
end

