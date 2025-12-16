defmodule FriendsWeb.HomeLive.Components.ChatComponents do
  @moduledoc """
  Function components for the chat panel logic.
  """
  use FriendsWeb, :html
  import FriendsWeb.HomeLive.Helpers

  attr :room, :map, required: true
  attr :current_user, :map, required: true
  attr :room_members, :list, default: []
  attr :room_messages, :list, default: []
  attr :new_chat_message, :string, default: ""
  attr :show_mobile_chat, :boolean, default: false
  attr :container_class, :string, default: nil
  attr :id_prefix, :string, default: "desktop"

  def chat_panel(assigns) do
    ~H"""
    <div class="contents">
      <%= if @show_mobile_chat do %>
        <%!-- Backdrop --%>
        <div
          class="lg:hidden fixed inset-0 z-40 bg-black/60 backdrop-blur-sm animate-in fade-in duration-300"
          phx-click="toggle_mobile_chat"
          phx-mounted={JS.add_class("overflow-hidden", to: "body")}
          phx-remove={JS.remove_class("overflow-hidden", to: "body")}
        ></div>
      <% end %>

      <div
        id={if @show_mobile_chat, do: "mobile-chat-drawer", else: "#{@id_prefix}-chat-panel"}
        phx-hook={if @show_mobile_chat, do: "SwipeableDrawer", else: nil}
        data-close-event="toggle_mobile_chat"
        class={
        @container_class ||
          if @show_mobile_chat,
            do:
              "fixed inset-x-0 bottom-0 z-50 h-[92vh] bg-[#0A0A0A] border-t border-white/10 shadow-[0_-10px_40px_rgba(0,0,0,0.8)] animate-in slide-in-from-bottom duration-300 rounded-t-3xl flex flex-col",
            else: "hidden lg:flex lg:flex-col fixed top-[84px] right-4 bottom-4 w-[380px] z-30"
      }>
        <%= if @show_mobile_chat do %>
          <%!-- Drag Handle Area --%>
          <div
            class="w-full pt-4 pb-2 flex flex-col items-center cursor-grab active:cursor-grabbing shrink-0 touch-none"
            phx-click="toggle_mobile_chat"
          >
            <div class="w-12 h-1.5 bg-neutral-700/50 rounded-full"></div>
            <%!-- Invisible larger tap target --%>
            <div class="absolute inset-x-0 top-0 h-12"></div>
          </div>
        <% end %>
      
      <div class={"flex flex-col flex-1 overflow-hidden #{if @show_mobile_chat, do: "", else: "aether-card shadow-2xl h-full"}"}>
        <%!-- Chat Header --%>
        <div class={"px-4 py-3 flex items-center justify-between shrink-0 bg-transparent border-b border-white/5 #{if @show_mobile_chat, do: "", else: "backdrop-blur-md"}"}>
          <div class="flex items-center gap-3">
            <span class="font-bold text-base text-white tracking-wide">
              Chat <span class="text-neutral-600 font-normal text-xs ml-1">{@room.name || "Room"}</span>
            </span>
            <span class="text-[9px] text-emerald-500 font-bold px-1.5 py-0.5 rounded bg-emerald-500/10 border border-emerald-500/20">
              E2E
            </span>
          </div>
          
          <%!-- Desktop Only Invite --%>
          <%= if not @show_mobile_chat and @room.room_type != "dm" do %>
            <button
              phx-click="open_invite_modal"
              class="text-xs font-bold uppercase tracking-wider text-neutral-400 hover:text-white cursor-pointer transition-colors"
            >
              + Invite
            </button>
          <% end %>
        </div>

         <%!-- Members Section --%>
        <%= if @room_members != [] do %>
          <div class="relative px-4 py-2 border-b border-white/5 shrink-0 z-40">
            <button 
              type="button"
              phx-click={Phoenix.LiveView.JS.toggle(to: "##{@id_prefix}-chat-members-list", in: "fade-in", out: "fade-out")}
              class="flex items-center gap-2 text-xs font-medium text-neutral-400 hover:text-white transition-colors w-full group"
            >
              <span class="text-neutral-500">●</span>
              <span>{length(@room_members)} Online</span>
            </button>

            <%!-- Toggleable Member List Overlay --%>
            <div 
              id={"#{@id_prefix}-chat-members-list"} 
              class="hidden absolute top-full left-0 right-0 mt-1 mx-2 p-2 bg-[#1A1A1A] border border-white/10 rounded-xl shadow-2xl max-h-60 overflow-y-auto"
            >
              <div class="space-y-1">
                <%= for member <- @room_members do %>
                  <div class="flex items-center gap-3 p-2 rounded hover:bg-white/5 transition-colors group">
                    <div
                      class="w-6 h-6 rounded-full flex items-center justify-center text-[10px] font-bold text-white border border-white/10"
                      style={"background-color: #{member_color(member)}"}
                    >
                      {String.first(member.user.username)}
                    </div>
                    <span class="text-xs text-neutral-300 group-hover:text-white truncate">
                      @{member.user.username}
                    </span>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>

         <%!-- Messages --%>
        <div
          id={"#{@id_prefix}-room-messages-container"}
          class="flex-1 overflow-y-auto overscroll-contain p-4 space-y-4 min-h-0 scroll-smooth"
          phx-hook="RoomChatScroll"
          data-room-id={@room.id}
        >
          <%= if @room_messages == [] do %>
            <div class="flex items-center justify-center h-full text-neutral-600">
              <div class="text-center">
                <p class="text-sm">No messages yet</p>
              </div>
            </div>
          <% else %>
            <%= for message <- @room_messages do %>
              <div class={"flex flex-col #{if message.sender_id == @current_user.id, do: "items-end", else: "items-start"}"}>
                
                <%= if message.sender_id != @current_user.id do %>
                  <span class="text-[10px] text-neutral-500 mb-1 ml-1">@{message.sender.username}</span>
                <% end %>

               <div class={"max-w-[85%] px-4 py-2.5 shadow-sm relative group #{if message.sender_id == @current_user.id, do: "bg-[#2A2A2A] text-white rounded-2xl rounded-tr-sm border border-white/5", else: "bg-black border border-white/10 text-neutral-300 rounded-2xl rounded-tl-sm"}"}>
                  
                  <%= if message.content_type == "voice" do %>
                    <div
                      class="flex items-center gap-3 min-w-[120px]"
                      id={"#{@id_prefix}-room-voice-#{message.id}"}
                      phx-hook="RoomVoicePlayer"
                      data-message-id={message.id}
                      data-room-id={@room.id}
                    >
                      <button class="w-8 h-8 rounded-full bg-white text-black flex items-center justify-center hover:bg-neutral-200 transition-colors cursor-pointer room-voice-play-btn text-xs font-bold shadow-sm active:scale-95">
                        ▶
                      </button>
                      <div class="flex-1 h-1 bg-white/20 rounded-full overflow-hidden">
                        <div
                          class="room-voice-progress h-full bg-white rounded-full"
                          style="width: 0%"
                        >
                        </div>
                      </div>
                      
                      <span class="text-[9px] font-mono font-medium opacity-70">
                        {format_voice_duration(message.metadata["duration_ms"])}
                      </span>
                      <span
                        class="hidden room-voice-data"
                        id={"#{@id_prefix}-room-msg-#{message.id}"}
                        data-encrypted={Base.encode64(message.encrypted_content)}
                        data-nonce={Base.encode64(message.nonce)}
                      >
                      </span>
                    </div>
                  <% else %>
                    <p
                      class="text-sm leading-relaxed room-decrypted-content break-words"
                      id={"#{@id_prefix}-room-msg-#{message.id}"}
                      data-encrypted={Base.encode64(message.encrypted_content)}
                      data-nonce={Base.encode64(message.nonce)}
                    >
                      <span class="text-neutral-600 text-xs">...</span>
                    </p>
                  <% end %>
                  
                  <div class={"text-[9px] font-medium mt-1 opacity-40 #{if message.sender_id == @current_user.id, do: "text-right", else: "text-left"}"}>
                    {Calendar.strftime(message.inserted_at, "%H:%M")}
                  </div>
                </div>
              </div>
            <% end %>
          <% end %>
        </div>

         <%!-- Message Input --%>
        <div class="p-3 bg-[#0A0A0A] border-t border-white/5 shrink-0">
          <div
            id={"#{@id_prefix}-room-message-input-area"}
            class="flex items-end gap-2"
            phx-hook="RoomChatEncryption"
            data-room-id={@room.id}
          >
            <div class="flex-1 bg-[#1A1A1A] border border-white/10 rounded-2xl flex items-center px-1 transition-colors focus-within:border-white/20">
              <input
                type="text"
                value={@new_chat_message}
                phx-keyup="update_chat_message"
                placeholder="Type a message..."
                class="w-full bg-transparent border-none px-3 py-3 text-sm focus:ring-0 text-white placeholder-neutral-600 leading-normal"
                id={"#{@id_prefix}-room-message-input"}
                autocomplete="off"
                autofocus
              />
            </div>
            <button
              id={"#{@id_prefix}-send-room-message-btn"}
              class="w-11 h-11 rounded-full bg-white text-black flex items-center justify-center transition-transform active:scale-95 cursor-pointer shadow-lg hover:bg-neutral-200"
            >
              <svg class="w-5 h-5 ml-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14 5l7 7m0 0l-7 7m7-7H3" />
              </svg>
            </button>
          </div>
      </div>
    </div>
    </div>
    </div>
    """
  end

  attr :show_mobile_chat, :boolean, default: false

  def mobile_chat_toggle(assigns) do
    ~H"""
    <%= if not @show_mobile_chat do %>
      <%!-- Pull-up bottom bar for chat --%>
      <button
        phx-click="toggle_mobile_chat"
        class="lg:hidden fixed bottom-0 inset-x-0 z-40 cursor-pointer group"
      >
        <div class="mx-auto max-w-md">
          <div class="aether-card rounded-t-2xl rounded-b-none border-b-0 px-4 py-2 flex items-center justify-center gap-2 group-hover:border-white/20 group-active:bg-white/5 transition-all">
            <%!-- Triangle arrow indicator --%>
            <svg class="w-4 h-4 text-neutral-500 group-hover:text-neutral-300 transition-colors" fill="currentColor" viewBox="0 0 24 24">
              <path d="M12 8l-6 6h12l-6-6z"/>
            </svg>
            <span class="text-xs font-bold text-neutral-500 uppercase tracking-wider group-hover:text-neutral-300 transition-colors">Chat</span>
            <%!-- E2E badge --%>
            <span class="text-[8px] text-emerald-400 font-bold flex items-center gap-0.5 border border-emerald-500/30 bg-emerald-500/10 px-1 rounded-sm">
              <span class="w-1 h-1 rounded-full bg-emerald-500"></span> E2E
            </span>
          </div>
        </div>
      </button>
    <% end %>
    """
  end
end

