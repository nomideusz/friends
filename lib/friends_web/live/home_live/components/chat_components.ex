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

  def chat_panel(assigns) do
    ~H"""
    <div class={
      @container_class ||
        if @show_mobile_chat,
          do:
            "fixed inset-0 z-50 bg-black/90 w-full pt-safe animate-in slide-in-from-right duration-300",
          else: "hidden lg:flex lg:flex-col fixed top-[84px] right-4 bottom-4 w-[380px] z-30"
    }>
      <%= if @show_mobile_chat do %>
        <button
          phx-click="toggle_mobile_chat"
          class="absolute top-3 right-3 z-50 p-2 bg-black/60 border border-white/10 rounded-full text-white shadow-lg cursor-pointer hover:bg-white/10 active:scale-95 transition-all"
        >
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M6 18L18 6M6 6l12 12"
            />
          </svg>
        </button>
      <% end %>
      
      <div class="aether-card overflow-hidden flex flex-col h-full shadow-2xl">
        <%!-- Chat Header with Invite --%>
        <div class={"px-4 py-3 border-b border-white/10 flex items-center justify-between shrink-0 bg-black/40 backdrop-blur-md #{if @show_mobile_chat, do: "pr-14", else: ""}"}>
          <div class="flex items-center gap-3">
            <span class="font-bold text-sm text-neutral-200 uppercase tracking-wider">Chat</span>
            <span class="text-[10px] text-emerald-400 font-bold flex items-center gap-1 border border-emerald-500/30 bg-emerald-500/10 px-1.5 rounded-sm">
              <span class="w-1.5 h-1.5 rounded-full bg-emerald-500 shadow-[0_0_5px_rgba(16,185,129,0.5)]"></span> E2E
            </span>
          </div>
          
          <%= if @room.room_type != "dm" do %>
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
          <div class="relative px-3 py-2 border-b border-white/10 shrink-0 bg-black/40 backdrop-blur-md z-40">
            <button 
              type="button"
              phx-click={Phoenix.LiveView.JS.toggle(to: "#chat-members-list", in: "fade-in", out: "fade-out")}
              class="flex items-center gap-2 text-xs font-bold text-neutral-400 hover:text-white transition-colors w-full group"
            >
              <span class="p-1 rounded bg-white/10 group-hover:bg-white/20 transition-colors">👥</span>
              <span>{length(@room_members)} Members</span>
              <span class="ml-auto text-[10px] text-neutral-600 group-hover:text-neutral-400">▼</span>
            </button>

            <%!-- Toggleable Member List Overlay --%>
            <div 
              id="chat-members-list" 
              class="hidden absolute top-full left-0 right-0 mt-1 mx-2 p-2 aether-card bg-black/95 shadow-2xl max-h-60 overflow-y-auto"
            >
              <div class="space-y-1">
                <%= for member <- @room_members do %>
                  <div class="flex items-center gap-3 p-2 rounded hover:bg-white/5 transition-colors group">
                    <div
                      class="w-8 h-8 rounded-full flex items-center justify-center text-xs font-bold text-white border border-white/10"
                      style={"background-color: #{member_color(member)}"}
                    >
                      {String.first(member.user.username)}
                    </div>
                    <div class="flex-1 min-w-0 text-left">
                      <p class="text-xs font-bold text-neutral-300 group-hover:text-white truncate">
                        @{member.user.username}
                      </p>
                      <p class="text-[10px] text-neutral-600 truncate">
                        {if member.user.id == @current_user.id, do: "You", else: "Online"}
                      </p>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>
         <%!-- Messages --%>
        <div
          id="room-messages-container"
          class="flex-1 overflow-y-auto overscroll-contain p-3 space-y-3 min-h-0"
          phx-hook="RoomChatScroll"
          data-room-id={@room.id}
        >
          <%= if @room_messages == [] do %>
            <div class="flex items-center justify-center h-full text-neutral-500">
              <div class="text-center">
                <p class="text-3xl mb-2">💬</p>
                
                <p class="text-sm">No messages yet</p>
              </div>
            </div>
          <% else %>
            <%= for message <- @room_messages do %>
              <div class={"flex #{if message.sender_id == @current_user.id, do: "justify-end", else: "justify-start"}"}>
               <div class={"max-w-[85%] rounded-2xl px-4 py-3 shadow-md backdrop-blur-sm border transition-all #{if message.sender_id == @current_user.id, do: "bg-white/10 border-white/10 text-white rounded-br-none", else: "bg-white/5 border-white/5 text-neutral-200 rounded-bl-none"}"}>
                  <%= if message.sender_id != @current_user.id do %>
                    <p class="text-[10px] font-bold text-neutral-500 mb-1 uppercase tracking-wider">@{message.sender.username}</p>
                  <% end %>
                  
                  <%= if message.content_type == "voice" do %>
                    <div
                      class="flex items-center gap-2"
                      id={"room-voice-#{message.id}"}
                      phx-hook="RoomVoicePlayer"
                      data-message-id={message.id}
                      data-room-id={@room.id}
                    >
                      <button class="w-8 h-8 rounded-full bg-white/10 border border-white/20 flex items-center justify-center hover:bg-white/20 transition-colors cursor-pointer room-voice-play-btn text-xs font-bold text-white shadow-sm active:translate-y-px">
                        ▶
                      </button>
                      <div class="flex-1 h-2 bg-white/10 rounded-full min-w-[60px] overflow-hidden">
                        <div
                          class="room-voice-progress h-full bg-white rounded-full shadow-[0_0_10px_rgba(255,255,255,0.5)]"
                          style="width: 0%"
                        >
                        </div>
                      </div>
                      
                      <span class="text-[10px] font-mono font-bold text-white/70">
                        {format_voice_duration(message.metadata["duration_ms"])}
                      </span>
                      <span
                        class="hidden"
                        id={"room-msg-#{message.id}"}
                        data-encrypted={Base.encode64(message.encrypted_content)}
                        data-nonce={Base.encode64(message.nonce)}
                      >
                      </span>
                    </div>
                  <% else %>
                    <p
                      class="text-sm room-decrypted-content font-medium leading-relaxed"
                      id={"room-msg-#{message.id}"}
                      data-encrypted={Base.encode64(message.encrypted_content)}
                      data-nonce={Base.encode64(message.nonce)}
                    >
                      <span class="text-neutral-400 italic text-xs animate-pulse">Decrypting...</span>
                    </p>
                  <% end %>
                  
                  <p class={"text-[9px] font-bold mt-1 uppercase tracking-wide #{if message.sender_id == @current_user.id, do: "text-white/50", else: "text-neutral-500"}"}>
                    {Calendar.strftime(message.inserted_at, "%H:%M")}
                  </p>
                </div>
              </div>
            <% end %>
          <% end %>
        </div>
         <%!-- Message Input --%>
        <div class="p-3 border-t border-white/10 shrink-0">
          <div
            id="room-message-input-area"
            class="flex items-center gap-2"
            phx-hook="RoomChatEncryption"
            data-room-id={@room.id}
          >
            <input
              type="text"
              value={@new_chat_message}
              phx-keyup="update_chat_message"
              placeholder="Message..."
              class="flex-1 bg-black/30 border border-white/10 rounded-full px-3 py-1.5 text-sm focus:outline-none focus:border-blue-500 text-white placeholder-neutral-500 transition-all"
              id="room-message-input"
              autocomplete="off"
            />
            <button
              id="send-room-message-btn"
              class="w-8 h-8 rounded-full bg-emerald-600 hover:bg-emerald-500 flex items-center justify-center transition-colors cursor-pointer text-sm"
            >
              ➤
            </button>
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
      <button
        phx-click="toggle_mobile_chat"
        class="lg:hidden fixed bottom-6 right-6 w-14 h-14 rounded-full bg-indigo-600 opal-aurora text-white shadow-xl z-40 flex items-center justify-center animate-in zoom-in slide-in-from-bottom-4 duration-300 border border-white/20 cursor-pointer"
      >
        <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"
          />
        </svg>
      </button>
    <% end %>
    """
  end
end
