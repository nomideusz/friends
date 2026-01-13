defmodule FriendsWeb.HomeLive.Components.FluidRoomChatComponents do
  @moduledoc """
  Chat-related components for private rooms.
  Provides the inline chat panel for room messaging.
  """
  use FriendsWeb, :html

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
