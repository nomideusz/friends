defmodule FriendsWeb.MessagesLive do
  @moduledoc """
  LiveView for E2E encrypted direct messages.
  Messages are encrypted client-side before being sent.
  """
  use FriendsWeb, :live_view
  alias Friends.Social

  @messages_per_page 50

  def mount(_params, session, socket) do
    user_id = session["user_id"]
    user = if user_id, do: Social.get_user(user_id)

    if is_nil(user) do
      {:ok,
       socket
       |> put_flash(:error, "You must be logged in to access messages")
       |> redirect(to: "/")}
    else
      if connected?(socket) do
        Social.subscribe_to_user_conversations(user.id)
      end

      conversations = Social.list_user_conversations(user.id)

      {:ok,
       socket
       |> assign(:current_user, user)
       |> assign(:conversations, conversations)
       |> assign(:active_conversation, nil)
       |> assign(:messages, [])
       |> assign(:new_message, "")
       |> assign(:show_new_chat_modal, false)
       |> assign(:friend_search, "")
       |> assign(:friend_search_results, [])
       |> assign(:recording_voice, false)
       |> assign(:page_title, "Messages")}
    end
  end

  def handle_params(%{"id" => conversation_id}, _uri, socket) do
    conv_id = String.to_integer(conversation_id)

    if Social.is_participant?(conv_id, socket.assigns.current_user.id) do
      Social.subscribe_to_conversation(conv_id)
      conversation = Social.get_conversation(conv_id)
      messages = Social.list_messages(conv_id, @messages_per_page)
      Social.mark_conversation_read(conv_id, socket.assigns.current_user.id)

      {:noreply,
       socket
       |> assign(:active_conversation, conversation)
       |> assign(:messages, messages)
       |> push_event("scroll_to_bottom", %{})}
    else
      {:noreply,
       socket
       |> put_flash(:error, "You don't have access to this conversation")
       |> redirect(to: ~p"/messages")}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, :active_conversation, nil)}
  end

  # --- Event Handlers ---

  def handle_event("search_friends", %{"query" => query}, socket) do
    results =
      if String.length(query) >= 2 do
        Social.search_users(query, socket.assigns.current_user.id)
      else
        []
      end

    {:noreply,
     socket
     |> assign(:friend_search, query)
     |> assign(:friend_search_results, results)}
  end

  def handle_event("start_conversation", %{"user_id" => user_id_str}, socket) do
    user_id = String.to_integer(user_id_str)

    case Social.get_or_create_direct_conversation(socket.assigns.current_user.id, user_id) do
      {:ok, conversation} ->
        {:noreply,
         socket
         |> assign(:show_new_chat_modal, false)
         |> push_navigate(to: ~p"/messages/#{conversation.id}")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not start conversation")}
    end
  end

  def handle_event("open_new_chat", _, socket) do
    {:noreply, assign(socket, :show_new_chat_modal, true)}
  end

  def handle_event("close_new_chat", _, socket) do
    {:noreply,
     socket
     |> assign(:show_new_chat_modal, false)
     |> assign(:friend_search, "")
     |> assign(:friend_search_results, [])}
  end

  def handle_event("update_message", %{"value" => text}, socket) do
    {:noreply, assign(socket, :new_message, text)}
  end

  def handle_event("update_message", %{"message" => text}, socket) do
    {:noreply, assign(socket, :new_message, text)}
  end

  def handle_event("send_message", %{"encrypted_content" => encrypted, "nonce" => nonce}, socket) do
    conversation = socket.assigns.active_conversation

    if conversation do
      case Social.send_message(
             conversation.id,
             socket.assigns.current_user.id,
             Base.decode64!(encrypted),
             "text",
             %{},
             Base.decode64!(nonce)
           ) do
        {:ok, _message} ->
          {:noreply, assign(socket, :new_message, "")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to send message")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("send_voice_note", %{"encrypted_content" => encrypted, "nonce" => nonce, "duration_ms" => duration}, socket) do
    conversation = socket.assigns.active_conversation

    if conversation do
      case Social.send_message(
             conversation.id,
             socket.assigns.current_user.id,
             Base.decode64!(encrypted),
             "voice",
             %{"duration_ms" => duration},
             Base.decode64!(nonce)
           ) do
        {:ok, _message} ->
          {:noreply, assign(socket, :recording_voice, false)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to send voice note")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("start_recording", _, socket) do
    {:noreply,
     socket
     |> assign(:recording_voice, true)
     |> push_event("start_voice_recording", %{})}
  end

  def handle_event("stop_recording", _, socket) do
    {:noreply,
     socket
     |> assign(:recording_voice, false)
     |> push_event("stop_voice_recording", %{})}
  end

  # --- PubSub Handlers ---

  def handle_info({:new_message, message}, socket) do
    if socket.assigns.active_conversation &&
       socket.assigns.active_conversation.id == message.conversation_id do
      messages = socket.assigns.messages ++ [message]
      Social.mark_conversation_read(message.conversation_id, socket.assigns.current_user.id)

      {:noreply,
       socket
       |> assign(:messages, messages)
       |> push_event("scroll_to_bottom", %{})
       |> push_event("decrypt_message", %{message_id: message.id})}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:new_message_notification, %{conversation_id: conv_id}}, socket) do
    # Refresh conversations list to update unread counts
    conversations = Social.list_user_conversations(socket.assigns.current_user.id)
    {:noreply, assign(socket, :conversations, conversations)}
  end

  # --- Render ---

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-black text-white flex">
      <%!-- Conversations Sidebar --%>
      <aside class="w-80 border-r border-white/10 flex flex-col">
        <div class="p-4 border-b border-white/10 flex items-center justify-between">
          <.link navigate={~p"/"} class="text-neutral-400 hover:text-white transition-colors">
            ← Back
          </.link>
          <h1 class="text-lg font-semibold">Messages</h1>
          <button
            phx-click="open_new_chat"
            class="w-8 h-8 rounded-full bg-white/10 hover:bg-white/20 flex items-center justify-center transition-colors cursor-pointer"
          >
            +
          </button>
        </div>

        <div class="flex-1 overflow-y-auto">
          <%= if @conversations == [] do %>
            <div class="p-4 text-center text-neutral-500">
              <p>No conversations yet</p>
              <button phx-click="open_new_chat" class="mt-2 text-blue-400 hover:text-blue-300 cursor-pointer">
                Start a chat
              </button>
            </div>
          <% else %>
            <%= for conv <- @conversations do %>
              <.link
                navigate={~p"/messages/#{conv.id}"}
                class={"block p-4 border-b border-white/5 hover:bg-white/5 transition-colors #{if @active_conversation && @active_conversation.id == conv.id, do: "bg-white/10"}"}
              >
                <div class="flex items-center gap-3">
                  <div class="w-10 h-10 rounded-full bg-gradient-to-br from-blue-500 to-purple-600 flex items-center justify-center text-sm font-bold">
                    {get_conversation_initial(conv, @current_user)}
                  </div>
                  <div class="flex-1 min-w-0">
                    <div class="flex items-center justify-between">
                      <span class="font-medium truncate">{get_conversation_name(conv, @current_user)}</span>
                      <%= if conv.unread_count > 0 do %>
                        <span class="w-5 h-5 rounded-full bg-blue-500 text-black text-xs font-bold flex items-center justify-center">
                          {conv.unread_count}
                        </span>
                      <% end %>
                    </div>
                    <%= if conv.latest_message do %>
                      <p class="text-sm text-neutral-500 truncate">
                        {message_preview(conv.latest_message)}
                      </p>
                    <% end %>
                  </div>
                </div>
              </.link>
            <% end %>
          <% end %>
        </div>
      </aside>

      <%!-- Chat Area --%>
      <main class="flex-1 flex flex-col">
        <%= if @active_conversation do %>
          <%!-- Chat Header --%>
          <header class="p-4 border-b border-white/10 flex items-center gap-3">
            <div class="w-10 h-10 rounded-full bg-gradient-to-br from-blue-500 to-purple-600 flex items-center justify-center text-sm font-bold">
              {get_conversation_initial(@active_conversation, @current_user)}
            </div>
            <div>
              <h2 class="font-semibold">{get_conversation_name(@active_conversation, @current_user)}</h2>
              <p class="text-xs text-emerald-400 flex items-center gap-1">
                <span class="w-2 h-2 rounded-full bg-emerald-400"></span>
                End-to-end encrypted
              </p>
            </div>
          </header>

          <%!-- Messages --%>
          <div id="messages-container" class="flex-1 overflow-y-auto p-4 space-y-4" phx-hook="MessagesScroll">
            <%= for message <- @messages do %>
              <div class={"flex #{if message.sender_id == @current_user.id, do: "justify-end", else: "justify-start"}"}>
                <div class={"max-w-[70%] rounded-2xl px-4 py-2 #{if message.sender_id == @current_user.id, do: "bg-blue-600", else: "bg-neutral-800"}"}>
                  <%= if message.content_type == "voice" do %>
                    <div class="flex items-center gap-2" id={"voice-#{message.id}"} phx-hook="VoicePlayer" data-message-id={message.id}>
                      <button class="w-8 h-8 rounded-full bg-white/20 flex items-center justify-center hover:bg-white/30 transition-colors cursor-pointer voice-play-btn">
                        ▶
                      </button>
                      <div class="flex-1 h-1 bg-white/20 rounded-full">
                        <div class="voice-progress h-full bg-white rounded-full" style="width: 0%"></div>
                      </div>
                      <span class="text-xs text-white/70 voice-duration">{format_duration(message.metadata["duration_ms"] || 0)}</span>
                      <%!-- Hidden element with encrypted data for JS to access --%>
                      <span class="hidden" id={"msg-#{message.id}"} data-encrypted={Base.encode64(message.encrypted_content)} data-nonce={Base.encode64(message.nonce)}></span>
                    </div>
                  <% else %>
                    <p class="text-sm decrypted-content" id={"msg-#{message.id}"} data-encrypted={Base.encode64(message.encrypted_content)} data-nonce={Base.encode64(message.nonce)}>
                      <span class="text-neutral-400 italic">Decrypting...</span>
                    </p>
                  <% end %>
                  <p class="text-[10px] text-white/50 mt-1">{format_time(message.inserted_at)}</p>
                </div>
              </div>
            <% end %>
          </div>

          <%!-- Message Input --%>
          <div class="p-4 border-t border-white/10">
            <div id="message-input-area" class="flex items-center gap-2" phx-hook="MessageEncryption" data-conversation-id={@active_conversation.id}>
              <button
                phx-click={if @recording_voice, do: "stop_recording", else: "start_recording"}
                class={"w-10 h-10 rounded-full flex items-center justify-center transition-colors cursor-pointer #{if @recording_voice, do: "bg-red-500 animate-pulse", else: "bg-white/10 hover:bg-white/20"}"}
              >
                🎤
              </button>
              <input
                type="text"
                value={@new_message}
                phx-keyup="update_message"
                phx-key="Enter"
                placeholder="Type a message..."
                class="flex-1 bg-neutral-900 border border-white/10 rounded-full px-4 py-2 text-sm focus:outline-none focus:border-white/30"
                id="message-input"
                autocomplete="off"
              />
              <button
                id="send-message-btn"
                class="w-10 h-10 rounded-full bg-blue-600 hover:bg-blue-500 flex items-center justify-center transition-colors cursor-pointer"
              >
                ➤
              </button>
            </div>
          </div>
        <% else %>
          <div class="flex-1 flex items-center justify-center text-neutral-500">
            <div class="text-center">
              <p class="text-4xl mb-4">💬</p>
              <p>Select a conversation or start a new chat</p>
            </div>
          </div>
        <% end %>
      </main>

      <%!-- New Chat Modal --%>
      <%= if @show_new_chat_modal do %>
        <div class="fixed inset-0 bg-black/80 flex items-center justify-center z-50" phx-click-away="close_new_chat">
          <div class="w-full max-w-md bg-neutral-900 rounded-2xl p-6 border border-white/10">
            <div class="flex items-center justify-between mb-4">
              <h2 class="text-lg font-semibold">New Chat</h2>
              <button phx-click="close_new_chat" class="text-neutral-500 hover:text-white cursor-pointer">×</button>
            </div>

            <form phx-change="search_friends" phx-submit="search_friends">
              <input
                type="text"
                name="query"
                value={@friend_search}
                placeholder="Search friends..."
                class="w-full bg-black border border-white/10 rounded-xl px-4 py-3 mb-4 focus:outline-none focus:border-white/30"
                autocomplete="off"
                phx-debounce="300"
              />
            </form>

            <div class="max-h-64 overflow-y-auto space-y-2">
              <%= for user <- @friend_search_results do %>
                <button
                  phx-click="start_conversation"
                  phx-value-user_id={user.id}
                  class="w-full flex items-center gap-3 p-3 rounded-xl hover:bg-white/5 transition-colors cursor-pointer text-left"
                >
                  <div class="w-10 h-10 rounded-full bg-gradient-to-br from-purple-500 to-pink-600 flex items-center justify-center font-bold">
                    {String.first(user.username) |> String.upcase()}
                  </div>
                  <div>
                    <p class="font-medium">@{user.username}</p>
                    <%= if user.display_name do %>
                      <p class="text-sm text-neutral-500">{user.display_name}</p>
                    <% end %>
                  </div>
                </button>
              <% end %>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # --- Helpers ---

  defp get_conversation_name(conversation, current_user) do
    case conversation.type do
      "group" -> conversation.name
      "direct" ->
        other = Enum.find(conversation.participants, fn p -> p.user_id != current_user.id end)
        if other && other.user, do: "@#{other.user.username}", else: "Unknown"
    end
  end

  defp get_conversation_initial(conversation, current_user) do
    name = get_conversation_name(conversation, current_user)
    name |> String.replace("@", "") |> String.first() |> String.upcase()
  end

  defp message_preview(%{content_type: "voice"}), do: "🎤 Voice note"
  defp message_preview(%{content_type: "image"}), do: "📷 Image"
  defp message_preview(_), do: "💬 Message"

  defp format_time(datetime) do
    Calendar.strftime(datetime, "%H:%M")
  end

  defp format_duration(ms) when is_integer(ms) do
    seconds = div(ms, 1000)
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)
    "#{minutes}:#{String.pad_leading(to_string(secs), 2, "0")}"
  end
  defp format_duration(_), do: "0:00"
end
