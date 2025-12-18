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

  def fluid_room(assigns) do
    ~H"""
    <div
      id="fluid-room"
      class="fixed inset-0 bg-black flex flex-col z-[100]"
      phx-hook="FriendsApp"
      phx-window-keydown="handle_keydown"
    >
      <%!-- Minimal Header --%>
      <.fluid_room_header
        room={@room}
        room_members={@room_members}
        current_user={@current_user}
        show_members_panel={@show_members_panel}
      />

      <%!-- Content Area (scrollable) --%>
      <div class="flex-1 overflow-y-auto overflow-x-hidden pb-24">
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

      <%!-- Fluid Chat Overlay (contextual) --%>
      <.fluid_chat_overlay
        room={@room}
        room_messages={@room_messages}
        current_user={@current_user}
        new_chat_message={@new_chat_message}
        chat_expanded={@chat_expanded}
        typing_users={@typing_users}
      />

      <%!-- Unified Input Bar (always visible at bottom) --%>
      <.unified_input_bar
        room={@room}
        uploads={@uploads}
        uploading={@uploading}
        recording_voice={@recording_voice}
        new_chat_message={@new_chat_message}
        chat_expanded={@chat_expanded}
      />

      <%!-- Members Sheet (bottom sheet) --%>
      <%= if @show_members_panel do %>
        <.members_sheet
          room={@room}
          room_members={@room_members}
          current_user={@current_user}
        />
      <% end %>
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

  def fluid_room_header(assigns) do
    ~H"""
    <div class="sticky top-0 z-50 px-4 py-3 flex items-center justify-between bg-gradient-to-b from-black via-black/90 to-transparent">
      <%!-- Back + Room Name --%>
      <div class="flex items-center gap-3">
        <.link
          navigate="/"
          class="w-8 h-8 rounded-full flex items-center justify-center text-white/50 hover:text-white hover:bg-white/10 transition-colors"
        >
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
          </svg>
        </.link>

        <button
          phx-click="toggle_members_panel"
          class="text-sm font-bold text-white truncate max-w-[200px] hover:text-white/80 transition-colors cursor-pointer"
        >
          {@room.name || @room.code}
        </button>
      </div>

      <%!-- Right Actions --%>
      <div class="flex items-center gap-3">
        <%!-- Members Pill --%>
        <button
          phx-click="toggle_members_panel"
          class="flex items-center gap-2 px-3 py-1.5 rounded-full bg-white/10 border border-white/10 hover:bg-white/20 hover:border-white/20 backdrop-blur-md transition-all cursor-pointer shadow-sm group"
        >
          <%!-- Stacked avatars --%>
          <div class="flex -space-x-2">
            <%= for member <- Enum.take(@room_members, 3) do %>
              <div
                class="w-5 h-5 rounded-full flex items-center justify-center text-[8px] font-bold text-white border border-black"
                style={"background-color: #{member_color(member)}"}
              >
                {String.first(member.user.username)}
              </div>
            <% end %>
          </div>
          <span class="text-xs font-medium text-white/70">{length(@room_members)}</span>
        </button>

        <%!-- User Avatar (Menu) --%>
        <button
          phx-click="toggle_user_menu"
          class="w-8 h-8 rounded-full bg-neutral-800/80 border border-white/10 flex items-center justify-center overflow-hidden hover:border-white/30 hover:bg-neutral-700/80 transition-all cursor-pointer"
        >
          <span class="text-xs font-bold text-white/80"><%= String.first(@current_user.username) |> String.upcase() %></span>
        </button>
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
    ~H"""
    <div
      id="fluid-items-grid"
      phx-update="stream"
      class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-1 p-1"
    >
      <%= for {dom_id, item} <- @items do %>
        <.fluid_content_item id={dom_id} item={item} room={@room} current_user={@current_user} />
      <% end %>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :item, :map, required: true
  attr :room, :map, required: true
  attr :current_user, :map, required: true

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
          <div class="absolute top-2 right-2 px-2 py-0.5 rounded-full bg-black/60 backdrop-blur-sm">
            <span class="text-[10px] font-bold text-white">{@item.photo_count}</span>
          </div>
          <%!-- Hover overlay --%>
          <div class="absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100 transition-opacity"></div>
        </div>

      <% :photo -> %>
        <%= if Map.get(@item, :content_type) == "audio/encrypted" do %>
          <%!-- Voice Note --%>
          <div
            id={@id}
            class="aspect-square relative overflow-hidden bg-neutral-900 flex items-center justify-center"
            phx-hook="GridVoicePlayer"
            data-item-id={@item.id}
            data-room-id={@room.id}
          >
            <div class="hidden" id={"grid-voice-data-#{@item.id}"} data-encrypted={@item.image_data} data-nonce={@item.thumbnail_data}></div>
            <button class="grid-voice-play-btn w-12 h-12 rounded-full bg-white/10 border border-white/20 flex items-center justify-center text-white hover:bg-white/20 transition-all cursor-pointer">
              <svg class="w-5 h-5 ml-0.5" fill="currentColor" viewBox="0 0 24 24">
                <path d="M8 5v14l11-7z" />
              </svg>
            </button>
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

            <%!-- Delete button (own photos only) --%>
            <%= if @item.user_id == @current_user.id do %>
              <button
                type="button"
                phx-click="delete_photo"
                phx-value-id={@item.id}
                data-confirm="Delete?"
                class="absolute top-2 right-2 w-6 h-6 rounded-full bg-black/60 text-white/70 hover:text-red-400 opacity-0 group-hover:opacity-100 transition-all cursor-pointer flex items-center justify-center"
              >
                <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
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

          <%!-- Delete button (own notes only) --%>
          <%= if @item.user_id == @current_user.id do %>
            <button
              type="button"
              phx-click="delete_note"
              phx-value-id={@item.id}
              data-confirm="Delete?"
              phx-click-stop
              class="absolute top-2 right-2 w-6 h-6 rounded-full bg-black/60 text-white/70 hover:text-red-400 opacity-0 group-hover:opacity-100 transition-all cursor-pointer flex items-center justify-center"
            >
              <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
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

  def fluid_chat_overlay(assigns) do
    has_messages = length(assigns.room_messages) > 0
    has_typing = map_size(assigns.typing_users) > 0
    assigns = assign(assigns, :has_messages, has_messages)
    assigns = assign(assigns, :has_typing, has_typing)

    ~H"""
    <%= if @has_messages or @chat_expanded or @has_typing do %>
      <div
        id="fluid-chat-overlay"
        class="fixed bottom-20 left-0 right-0 z-40 pointer-events-none"
        phx-hook="RoomChatScroll"
        data-room-id={@room.id}
      >
        <div class="max-w-lg mx-auto px-4 pointer-events-auto">
          <%!-- Chat container with glass effect --%>
          <div class="bg-black/80 backdrop-blur-xl border border-white/10 rounded-2xl overflow-hidden shadow-2xl animate-in slide-in-from-bottom-4 duration-300">
            <%!-- Collapse handle --%>
            <button
              phx-click="toggle_chat_expanded"
              class="w-full py-2 flex justify-center cursor-pointer hover:bg-white/5 transition-colors"
            >
              <div class="w-8 h-1 rounded-full bg-white/20"></div>
            </button>

            <%!-- Messages --%>
            <div class="max-h-[40vh] overflow-y-auto px-4 pb-4 space-y-3">
              <%= for message <- @room_messages do %>
                <div class={"flex flex-col #{if message.sender_id == @current_user.id, do: "items-end", else: "items-start"}"}>
                  <%= if message.sender_id != @current_user.id do %>
                    <span class="text-[10px] text-white/30 mb-1 ml-1">@{message.sender.username}</span>
                  <% end %>

                  <div class={"max-w-[85%] px-3 py-2 rounded-2xl #{if message.sender_id == @current_user.id, do: "bg-white/10 rounded-tr-sm", else: "bg-white/5 rounded-tl-sm"}"}>
                    <%= if message.content_type == "voice" do %>
                      <%!-- Voice message --%>
                      <div
                        class="flex items-center gap-2"
                        id={"chat-voice-#{message.id}"}
                        phx-hook="RoomVoicePlayer"
                        data-message-id={message.id}
                        data-room-id={@room.id}
                      >
                        <button class="room-voice-play-btn w-7 h-7 rounded-full bg-white/20 flex items-center justify-center text-white text-xs cursor-pointer">▶</button>
                        <div class="flex-1 h-1 bg-white/20 rounded-full">
                          <div class="room-voice-progress h-full bg-white rounded-full" style="width: 0%"></div>
                        </div>
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
                </div>
              <% end %>

              <%!-- Live Typing Indicators (Ghost Messages) --%>
              <%= for {user_id, typing_info} <- @typing_users do %>
                <div class="flex flex-col items-start animate-in fade-in duration-200" id={"typing-#{user_id}"}>
                  <span class="text-[10px] text-blue-400/60 mb-1 ml-1">@{typing_info.username} is typing...</span>
                  <div class="max-w-[85%] px-3 py-2 rounded-2xl bg-blue-500/10 rounded-tl-sm border border-blue-500/20">
                    <p class="text-sm text-white/40 italic">
                      {typing_info.text}<span class="animate-pulse">│</span>
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

  def unified_input_bar(assigns) do
    ~H"""
    <div class="fixed bottom-0 left-0 right-0 z-50 p-4 bg-gradient-to-t from-black via-black/95 to-transparent">
      <div class="max-w-lg mx-auto">
        <div
          id="unified-input-area"
          class="flex items-center gap-2 bg-white/5 backdrop-blur-xl border border-white/10 rounded-full px-2 py-1.5 shadow-2xl"
          phx-hook="RoomChatEncryption"
          data-room-id={@room.id}
        >
          <%!-- Photo button --%>
          <form id="fluid-upload-form" phx-change="validate" phx-submit="save" class="contents">
            <label class="w-9 h-9 rounded-full flex items-center justify-center text-white/50 hover:text-white hover:bg-white/10 transition-colors cursor-pointer">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
              </svg>
              <%= if @uploads && @uploads[:photo] do %>
                <.live_file_input upload={@uploads.photo} class="sr-only" />
              <% end %>
            </label>
          </form>

          <%!-- Text input --%>
          <input
            type="text"
            value={@new_chat_message}
            phx-keyup="update_chat_message"
            placeholder="..."
            class="flex-1 bg-transparent border-none text-sm text-white placeholder-white/30 focus:ring-0 focus:outline-none py-2"
            id="unified-message-input"
            autocomplete="off"
          />

          <%!-- Voice button --%>
          <button
            id="fluid-voice-btn"
            phx-hook="GridVoiceRecorder"
            data-room-id={@room.id}
            class={"w-9 h-9 rounded-full flex items-center justify-center transition-colors cursor-pointer #{if @recording_voice, do: "bg-red-500 text-white animate-pulse", else: "text-white/50 hover:text-white hover:bg-white/10"}"}
          >
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z" />
            </svg>
          </button>

          <%!-- Send button --%>
          <button
            id="send-unified-message-btn"
            class="w-9 h-9 rounded-full bg-white text-black flex items-center justify-center hover:bg-white/90 transition-colors cursor-pointer"
          >
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M14 5l7 7m0 0l-7 7m7-7H3" />
            </svg>
          </button>
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
  # MEMBERS SHEET
  # Bottom sheet for managing members
  # ============================================================================

  attr :room, :map, required: true
  attr :room_members, :list, default: []
  attr :current_user, :map, required: true

  def members_sheet(assigns) do
    ~H"""
    <div class="fixed inset-0 z-[150]" phx-window-keydown="toggle_members_panel" phx-key="escape">
      <%!-- Backdrop --%>
      <div
        class="absolute inset-0 bg-black/70 backdrop-blur-sm animate-in fade-in duration-200"
        phx-click="toggle_members_panel"
      ></div>

      <%!-- Sheet --%>
      <div class="absolute inset-x-0 bottom-0 z-10 flex justify-center animate-in slide-in-from-bottom duration-300">
        <div class="w-full max-w-lg bg-neutral-900/95 backdrop-blur-xl border-t border-x border-white/10 rounded-t-3xl shadow-2xl max-h-[80vh] flex flex-col">
          <%!-- Handle --%>
          <div class="py-3 flex justify-center cursor-pointer" phx-click="toggle_members_panel">
            <div class="w-10 h-1 rounded-full bg-white/20"></div>
          </div>

          <%!-- Header --%>
          <div class="px-4 pb-4 flex items-center justify-between">
            <h2 class="text-lg font-bold text-white">{@room.name || @room.code}</h2>
            <span class="text-xs text-white/40">{length(@room_members)} members</span>
          </div>

          <%!-- Members List --%>
          <div class="flex-1 overflow-y-auto px-4 pb-8 space-y-2">
            <%= for member <- @room_members do %>
              <div class="flex items-center gap-3 p-3 rounded-xl bg-white/5 border border-white/5">
                <div
                  class="w-10 h-10 rounded-full flex items-center justify-center text-sm font-bold text-white"
                  style={"background-color: #{member_color(member)}"}
                >
                  {String.first(member.user.username)}
                </div>
                
                <div class="flex-1 min-w-0">
                  <div class="flex items-center gap-2">
                    <span class="text-sm font-medium text-white truncate">@{member.user.username}</span>
                    <%= if @room.owner_id == member.user.id do %>
                      <span class="text-[10px] text-yellow-500 bg-yellow-500/10 px-1.5 py-0.5 rounded border border-yellow-500/20">Owner</span>
                    <% end %>
                  </div>
                  <div class="text-[10px] text-white/40">
                    Joined {Calendar.strftime(member.inserted_at, "%b %d")}
                  </div>
                </div>

                <%!-- Actions (if admin/owner) --%>
                <% is_owner = @room.owner_id == @current_user.id %>
                <% is_self = member.user.id == @current_user.id %>
                
                <%= if is_owner and not is_self do %>
                  <button
                    phx-click="remove_member"
                    phx-value-user_id={member.user.id}
                    data-confirm={"Remove #{member.user.username} from group?"}
                    class="text-xs text-red-400 hover:text-red-300 transition-colors px-2 py-1"
                  >
                    Remove
                  </button>
                <% end %>
              </div>
            <% end %>

            <%!-- Invite Button --%>
            <%= if @room.room_type != "dm" do %>
              <button
                phx-click="open_invite_sheet"
                class="w-full mt-4 py-3 rounded-xl bg-white/10 border border-white/10 hover:bg-white/20 text-sm font-medium text-white transition-colors flex items-center justify-center gap-2"
              >
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M18 9v3m0 0v3m0-3h3m-3 0h-3m-2-5a4 4 0 11-8 0 4 4 0 018 0zM3 20a6 6 0 0112 0v1H3v-1z" />
                </svg>
                Invite People
              </button>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

end

