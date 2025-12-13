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
  # Event names are hardcoded in template (e.g. toggle_mobile_chat, update_chat_message)

  def chat_panel(assigns) do
    ~H"""
    <div class={
      if @show_mobile_chat,
        do:
          "fixed inset-0 z-50 bg-neutral-900 w-full pt-safe animate-in slide-in-from-right duration-300",
        else: "hidden lg:flex lg:flex-col fixed top-[84px] right-4 bottom-4 w-[380px] z-30"
    }>
      <%= if @show_mobile_chat do %>
        <button
          phx-click="toggle_mobile_chat"
          class="absolute top-4 right-4 z-50 p-2 bg-neutral-800 rounded-full text-white shadow-lg cursor-pointer"
        >
          <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M6 18L18 6M6 6l12 12"
            />
          </svg>
        </button>
      <% end %>
      
      <div class="opal-card rounded-2xl overflow-hidden flex flex-col h-full border border-white/5">
        <%!-- Chat Header with Invite --%>
        <div class="px-4 py-3 border-b border-white/5 flex items-center justify-between shrink-0">
          <div class="flex items-center gap-3">
            <span class="font-medium text-sm text-white">Chat</span>
            <span class="text-[10px] text-emerald-400 flex items-center gap-1">
              <span class="w-1.5 h-1.5 rounded-full bg-emerald-400"></span> E2E
            </span>
          </div>
          
          <%= if @room.room_type != "dm" do %>
            <button
              phx-click="open_invite_modal"
              class="text-xs text-neutral-400 hover:text-white cursor-pointer transition-colors"
            >
              + Invite
            </button>
          <% end %>
        </div>
         <%!-- Members Section --%>
        <%= if @room_members != [] do %>
          <div class="px-3 py-2 border-b border-white/5 shrink-0">
            <div class="flex items-center gap-2">
              <%!-- Stacked avatars --%>
              <div class="flex -space-x-2 overflow-hidden">
                <%= for member <- Enum.take(@room_members, 5) do %>
                  <div
                    class="inline-block w-6 h-6 rounded-full ring-2 ring-neutral-900 flex items-center justify-center text-[9px] font-bold text-white relative z-10"
                    style={"background-color: #{member_color(member)}"}
                  >
                    {String.first(member.user.username)}
                  </div>
                <% end %>
                
                <%= if length(@room_members) > 5 do %>
                  <div class="w-6 h-6 rounded-full border-2 border-neutral-900 bg-neutral-700 flex items-center justify-center text-[9px] font-medium text-neutral-300 relative z-0">
                    +{length(@room_members) - 5}
                  </div>
                <% end %>
              </div>
               <span class="text-[10px] text-neutral-500">{length(@room_members)} members</span>
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
                <div class={"max-w-[85%] rounded-xl px-3 py-2 #{if message.sender_id == @current_user.id, do: "bg-emerald-600", else: "bg-neutral-800"}"}>
                  <%= if message.sender_id != @current_user.id do %>
                    <p class="text-[10px] text-neutral-400 mb-0.5">@{message.sender.username}</p>
                  <% end %>
                  
                  <%= if message.content_type == "voice" do %>
                    <div
                      class="flex items-center gap-2"
                      id={"room-voice-#{message.id}"}
                      phx-hook="RoomVoicePlayer"
                      data-message-id={message.id}
                      data-room-id={@room.id}
                    >
                      <button class="w-6 h-6 rounded-full bg-white/20 flex items-center justify-center hover:bg-white/30 transition-colors cursor-pointer room-voice-play-btn text-xs">
                        ▶
                      </button>
                      <div class="flex-1 h-1 bg-white/20 rounded-full min-w-[60px]">
                        <div
                          class="room-voice-progress h-full bg-white rounded-full"
                          style="width: 0%"
                        >
                        </div>
                      </div>
                      
                      <span class="text-[10px] text-white/70">
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
                      class="text-sm room-decrypted-content"
                      id={"room-msg-#{message.id}"}
                      data-encrypted={Base.encode64(message.encrypted_content)}
                      data-nonce={Base.encode64(message.nonce)}
                    >
                      <span class="text-neutral-400 italic text-xs">Decrypting...</span>
                    </p>
                  <% end %>
                  
                  <p class="text-[9px] text-white/50 mt-1">
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
              class="flex-1 bg-neutral-900 border border-white/10 rounded-full px-3 py-1.5 text-sm focus:outline-none focus:border-white/30 text-white"
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
