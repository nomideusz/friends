defmodule FriendsWeb.HomeLive.Components.FeedComponents do
  @moduledoc """
  Function components for the home feed UI.
  """
  use FriendsWeb, :html
  # alias Phoenix.LiveView.JS

  # --- Components ---

  attr :uploads, :map, required: true
  attr :uploading, :boolean, default: false
  attr :recording_voice, :boolean, default: false

  def feed_upload_progress(assigns) do
    ~H"""
    <%= if @uploads && @uploads[:feed_photo] do %>
      <%= for entry <- @uploads.feed_photo.entries do %>
        <div class="mb-4 aether-card p-3">
          <div class="flex items-center gap-3">
            <div class="flex-1 bg-white/10 h-2 rounded-full overflow-hidden border border-white/5">
              <div class="bg-blue-500 h-full transition-all duration-300 shadow-[0_0_10px_rgba(59,130,246,0.5)]" style={"width: #{entry.progress}%"} />
            </div>
            <span class="text-xs text-neutral-400 font-bold font-mono">{entry.progress}%</span>
            <button
              type="button"
              phx-click="cancel_upload"
              phx-value-ref={entry.ref}
              class="text-neutral-500 hover:text-white text-xs font-bold uppercase tracking-wider cursor-pointer transition-colors"
            >
              cancel
            </button>
          </div>
        </div>
      <% end %>
    <% end %>
    """
  end

  # Delegate to shared CardComponents
  alias FriendsWeb.HomeLive.Components.CardComponents

  def feed_actions_bar(assigns) do
    assigns = assign(assigns, :upload_key, :feed_photo)
    ~H"""
    <CardComponents.actions_bar
      uploads={@uploads}
      uploading={@uploading}
      recording_voice={@recording_voice}
      note_event="open_feed_note_modal"
      voice_button_id="feed-voice-record"
      voice_hook="FeedVoiceRecorder"
      upload_key={:feed_photo}
    />
    """
  end

  def empty_feed(assigns) do
    ~H"""
    <div class="text-center py-20 aether-card shadow-inner">
      <div class="mb-4">
        <svg
          class="w-16 h-16 mx-auto text-neutral-400"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="1.5"
            d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"
          >
          </path>
        </svg>
      </div>
      
      <p class="text-neutral-200 text-lg font-bold uppercase tracking-wide mb-2">Your feed is empty</p>
      
      <p class="text-neutral-500 text-sm">Post a photo, note, or voice message to get started</p>
    </div>
    """
  end

  attr :feed_items, :list, required: true

  def feed_grid(assigns) do
    ~H"""
    <div
      id="public-feed-grid"
      phx-update="stream"
      phx-hook="PhotoGrid"
      class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-3 xl:grid-cols-4 gap-4"
    >
      <%= for {dom_id, item} <- @feed_items do %>
        <.feed_item id={dom_id} item={item} />
      <% end %>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :item, :map, required: true

  def feed_item(assigns) do
    ~H"""
    <%= if @item.type == :photo or @item.type == "photo" do %>
      <div
        id={@id}
        class="photo-item aether-card group relative aspect-square overflow-hidden cursor-pointer transition-all hover:-translate-y-1 animate-in fade-in zoom-in-95 duration-300"
        phx-click="view_feed_photo"
        phx-value-photo_id={@item.id}
      >
        <%= if is_binary(@item[:content_type]) && String.starts_with?(@item.content_type, "audio/") do %>
          <div class="w-full h-full flex flex-col items-center justify-center p-3 sm:p-4 text-center relative overflow-hidden" onclick="event.stopPropagation();">
            <!-- Decorative wave background -->
            <div class="absolute inset-0 opacity-10" style="background-image: url('data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMjAiIGhlaWdodD0iMjAiIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyI+PHBhdGggZD0iTTEgMTBoMThNMTAgMXYxOCIgc3Ryb2tlPSJjdXJyZW50Q29xvciBzdHJva2Utd2lkdGg9IjIiIGZpbGw9Im5vbmUiIC8+PC9zdmc+');"></div>
            
            <div class="relative z-10 flex flex-col items-center w-full">
              <div class="w-10 h-10 sm:w-12 sm:h-12 rounded-full bg-white/10 flex items-center justify-center mb-2 sm:mb-3 ring-1 ring-white/20 group-hover:scale-110 transition-transform duration-300">
                <svg class="w-5 h-5 sm:w-6 sm:h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z" />
                </svg>
              </div>
              
              <span class="text-[10px] font-medium text-neutral-400 uppercase tracking-widest mb-2">Voice Note</span>
              
              <audio controls src={@item.image_data} class="w-full h-6 sm:h-7 max-w-[120px] sm:max-w-[140px] opacity-90 hover:opacity-100 transition-opacity" style="transform: scale(0.85);" onclick="event.stopPropagation();" />
              
              <div class="mt-2 flex items-center gap-1 px-2 py-0.5 rounded-full bg-neutral-900 border border-white/10 shadow-sm">
                <div class="w-2 h-2 rounded-full bg-blue-500 animate-pulse"></div>
                <span class="text-[10px] text-neutral-400 font-medium">@{@item.user_name || "unknown"}</span>
              </div>
            </div>
          </div>
        <% else %>
          <img
            src={@item.thumbnail_data || @item[:image_data]}
            alt="Feed photo"
            class="w-full h-full object-cover"
          />
          <div class="absolute inset-0 bg-gradient-to-t from-black/60 via-transparent to-transparent opacity-0 group-hover:opacity-100 transition-opacity">
            <div class="absolute bottom-2 left-2 right-2">
              <div class="text-xs font-bold text-neutral-500 truncate">@{@item.user_name || "unknown"}</div>
            </div>
          </div>
        <% end %>
      </div>
    <% else %>
      <%!-- Note item --%>
      <div
        id={@id}
        class="note-item aether-card group relative aspect-square overflow-hidden cursor-pointer transition-all hover:-translate-y-1 animate-in fade-in zoom-in-95 duration-300"
        phx-click="view_feed_note"
        phx-value-note_id={@item.id}
      >
        <div class="w-full h-full p-4 flex flex-col">
          <div class="flex-1 overflow-hidden">
            <p class="text-sm text-neutral-200 line-clamp-6">{@item.content || ""}</p>
          </div>
          
          <div class="mt-2 pt-2 border-t border-neutral-200">
            <div class="flex items-center gap-2">
              <div
                class="w-5 h-5 rounded-full"
                style={"background-color: #{@item.user_color || "#888"}"}
              >
              </div>
               <span class="text-xs text-neutral-500 truncate">@{@item.user_name || "unknown"}</span>
            </div>
          </div>
        </div>
      </div>
    <% end %>
    """
  end
end
