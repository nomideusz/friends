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

  def feed_actions_bar(assigns) do
    ~H"""
    <div class="mb-6 flex items-stretch gap-3">
      <%!-- Photo Upload --%>
      <%= if @uploads && @uploads[:feed_photo] do %>
        <form
          id="feed-upload-form"
          phx-change="validate_feed_photo"
          phx-submit="save_feed_photo"
          class="contents"
        >
          <label
            for={@uploads.feed_photo.ref}
            class="flex-1 flex items-center justify-center gap-2 py-3 px-4 rounded-lg btn-aether cursor-pointer"
          >
            <div class="w-8 h-8 rounded-full border border-white/20 flex items-center justify-center group-hover:scale-105 transition-transform bg-white/5">
              <span class="text-lg text-white group-hover:drop-shadow-[0_0_5px_rgba(255,255,255,0.8)] font-bold">+</span>
            </div>
            
            <span class="text-sm font-bold uppercase tracking-wider text-neutral-400 group-hover:text-white">
              {if @uploading, do: "Uploading...", else: "Photo"}
            </span> <.live_file_input upload={@uploads.feed_photo} class="sr-only" />
          </label>
        </form>
      <% end %>
       <%!-- Note Button --%>
      <button
        type="button"
        phx-click="open_feed_note_modal"
        class="flex-1 flex items-center justify-center gap-2 py-3 px-4 rounded-lg btn-aether cursor-pointer group"
      >
        <div class="w-8 h-8 rounded-full border border-white/20 flex items-center justify-center bg-white/5">
            <span class="text-lg text-white group-hover:drop-shadow-[0_0_5px_rgba(255,255,255,0.8)] font-bold">+</span>
        </div>
        <span class="text-sm font-bold uppercase tracking-wider text-neutral-400 group-hover:text-white">Note</span>
      </button> <%!-- Voice Button --%>
      <button
        type="button"
        id="feed-voice-record"
        phx-hook="FeedVoiceRecorder"
        class={"flex-1 flex items-center justify-center gap-2 py-3 px-4 rounded-lg btn-aether cursor-pointer group #{if @recording_voice, do: "border-blue-500 shadow-[0_0_10px_rgba(59,130,246,0.3)]", else: ""}"}
      >
        <div class={"w-8 h-8 rounded-full flex items-center justify-center border #{if @recording_voice, do: "bg-blue-600 border-blue-500 animate-pulse", else: "bg-white/5 border-white/20"}"}>
            <span class={"text-lg font-bold #{if @recording_voice, do: "text-white", else: "text-white group-hover:drop-shadow-[0_0_5px_rgba(255,255,255,0.8)]"}"}>
            {if @recording_voice, do: "●", else: "+"}
            </span>
        </div>
        <span class={"text-sm font-bold uppercase tracking-wider #{if @recording_voice, do: "text-blue-400", else: "text-neutral-400 group-hover:text-white"}"}>
          {if @recording_voice, do: "Recording...", else: "Voice"}
        </span>
      </button>
    </div>
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
        class="photo-item group relative aspect-square overflow-hidden rounded-xl border border-white/10 bg-black/50 cursor-pointer transition-all hover:shadow-[0_0_20px_rgba(255,255,255,0.1)] hover:-translate-y-1 animate-in fade-in zoom-in-95 duration-300"
        phx-click="view_feed_photo"
        phx-value-photo_id={@item.id}
      >
        <%= if String.starts_with?(@item.content_type || "", "audio/") do %>
          <div class="w-full h-full flex flex-col items-center justify-center p-6 bg-gradient-to-br from-neutral-900 to-neutral-800 opal-aurora text-center relative overflow-hidden">
            <!-- Decorative wave background -->
            <div class="absolute inset-0 opacity-10" style="background-image: url('data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMjAiIGhlaWdodD0iMjAiIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyI+PHBhdGggZD0iTTEgMTBoMThNMTAgMXYxOCIgc3Ryb2tlPSJjdXJyZW50Q29xvciBzdHJva2Utd2lkdGg9IjIiIGZpbGw9Im5vbmUiIC8+PC9zdmc+');"></div>
            
            <div class="relative z-10 flex flex-col items-center w-full">
              <div class="w-16 h-16 rounded-full bg-cyan-500/20 flex items-center justify-center mb-4 ring-1 ring-cyan-500/30 shadow-[0_0_15px_rgba(6,182,212,0.15)] group-hover:scale-110 transition-transform duration-300">
                <svg class="w-8 h-8 text-cyan-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z" />
                </svg>
              </div>
              
              <span class="text-xs font-medium text-cyan-200/70 uppercase tracking-widest mb-3">Voice Note</span>
              
              <audio controls src={@item.image_data} class="w-full h-8 max-w-[180px] opacity-90 hover:opacity-100 transition-opacity" onclick="event.stopPropagation();" />
              
              <div class="mt-4 flex items-center gap-2 px-3 py-1 rounded-full bg-neutral-900 border border-neutral-200 shadow-sm">
                <div class="w-2 h-2 rounded-full bg-green-500 animate-pulse"></div>
                <span class="text-[10px] text-neutral-400 font-medium">@{@item.user_name}</span>
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
              <div class="text-xs font-bold text-neutral-500 truncate">@{@item.user_name}</div>
            </div>
          </div>
        <% end %>
      </div>
    <% else %>
      <%!-- Note item --%>
      <div
        id={@id}
        class="photo-item opal-shimmer group relative aspect-square overflow-hidden rounded-2xl border border-white/5 hover:border-cyan-500/20 transition-all hover:shadow-xl hover:shadow-cyan-500/10 animate-in fade-in zoom-in-95 duration-300 cursor-pointer"
        phx-click="view_feed_note"
        phx-value-note_id={@item.id}
      >
        <div class="w-full h-full p-4 flex flex-col opal-aurora">
          <div class="flex-1 overflow-hidden">
            <p class="text-sm text-neutral-200 line-clamp-6">{@item.content}</p>
          </div>
          
          <div class="mt-2 pt-2 border-t border-neutral-200">
            <div class="flex items-center gap-2">
              <div
                class="w-5 h-5 rounded-full"
                style={"background-color: #{@item.user_color || "#888"}"}
              >
              </div>
               <span class="text-xs text-neutral-500 truncate">@{@item.user_name}</span>
            </div>
          </div>
        </div>
      </div>
    <% end %>
    """
  end
end
