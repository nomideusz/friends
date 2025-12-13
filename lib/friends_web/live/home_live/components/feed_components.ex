defmodule FriendsWeb.HomeLive.Components.FeedComponents do
  @moduledoc """
  Function components for the home feed UI.
  """
  use FriendsWeb, :html
  alias Phoenix.LiveView.JS

  # --- Components ---

  attr :uploads, :map, required: true
  attr :uploading, :boolean, default: false
  attr :recording_voice, :boolean, default: false

  def feed_upload_progress(assigns) do
    ~H"""
    <%= if @uploads && @uploads[:feed_photo] do %>
      <%= for entry <- @uploads.feed_photo.entries do %>
        <div class="mb-4 bg-neutral-900 p-3 rounded-lg border border-white/5">
          <div class="flex items-center gap-3">
            <div class="flex-1 bg-neutral-800 h-1 rounded-full overflow-hidden">
              <div class="bg-cyan-500 h-full transition-all duration-300" style={"width: #{entry.progress}%"} />
            </div>
            <span class="text-xs text-neutral-500 font-mono">{entry.progress}%</span>
            <button
              type="button"
              phx-click="cancel_upload"
              phx-value-ref={entry.ref}
              class="text-neutral-500 hover:text-white text-xs cursor-pointer"
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
            class="flex-1 flex items-center justify-center gap-2 py-3 px-4 rounded-xl glass border border-white/10 hover:border-white/20 cursor-pointer transition-all"
          >
            <div class="w-8 h-8 rounded-full bg-rose-500/10 flex items-center justify-center group-hover:scale-110 transition-transform">
              <svg class="w-4 h-4 text-rose-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"
                />
              </svg>
            </div>
            
            <span class="text-sm text-neutral-400 group-hover:text-rose-400">
              {if @uploading, do: "Uploading...", else: "Photo"}
            </span> <.live_file_input upload={@uploads.feed_photo} class="sr-only" />
          </label>
        </form>
      <% end %>
       <%!-- Note Button --%>
      <button
        type="button"
        phx-click="open_feed_note_modal"
        class="flex-1 flex items-center justify-center gap-2 py-3 px-4 rounded-xl glass border border-white/10 hover:border-white/20 cursor-pointer transition-all"
      >
        <span class="text-lg text-neutral-400">+</span>
        <span class="text-sm text-neutral-400">Note</span>
      </button> <%!-- Voice Button --%>
      <button
        type="button"
        id="feed-voice-record"
        phx-hook="FeedVoiceRecorder"
        class={"flex-1 flex items-center justify-center gap-2 py-3 px-4 rounded-xl glass border cursor-pointer transition-all #{if @recording_voice, do: "border-red-500 bg-red-500/10", else: "border-white/10 hover:border-white/20"}"}
      >
        <span class={"text-lg #{if @recording_voice, do: "text-red-400", else: "text-neutral-400"}"}>
          {if @recording_voice, do: "●", else: "+"}
        </span>
        <span class={"text-sm #{if @recording_voice, do: "text-red-400", else: "text-neutral-400"}"}>
          {if @recording_voice, do: "Recording...", else: "Voice"}
        </span>
      </button>
    </div>
    """
  end

  def empty_feed(assigns) do
    ~H"""
    <div class="text-center py-20 opal-card rounded-2xl">
      <div class="mb-4 opacity-40">
        <svg
          class="w-16 h-16 mx-auto text-neutral-500"
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
      
      <p class="text-neutral-500 text-base font-medium mb-2">Your feed is empty</p>
      
      <p class="text-neutral-600 text-sm">Post a photo, note, or voice message to get started</p>
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
    <%= if @item.type == "photo" do %>
      <div
        id={@id}
        class="photo-item opal-shimmer group relative aspect-square overflow-hidden rounded-2xl border border-white/5 hover:border-white/20 cursor-pointer transition-all hover:shadow-xl hover:shadow-violet-500/10 animate-in fade-in zoom-in-95 duration-300"
        phx-click="view_feed_photo"
        phx-value-photo_id={@item.id}
      >
        <%= if String.starts_with?(@item.content_type || "", "audio/") do %>
          <div class="w-full h-full flex flex-col items-center justify-center p-4 bg-neutral-900/50 opal-aurora text-center">
            <div class="w-12 h-12 rounded-full bg-cyan-500/20 flex items-center justify-center mb-2">
              <svg class="w-6 h-6 text-cyan-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z" />
              </svg>
            </div>
            <span class="text-xs text-neutral-400 mb-2">Voice Note</span>
            
            <audio controls src={@item.image_data} class="w-full h-8 max-w-[140px]" />
            
            <span class="text-[10px] text-neutral-600 mt-2">@{@item.user_name}</span>
          </div>
        <% else %>
          <img
            src={@item.thumbnail_data || @item[:image_data]}
            alt="Feed photo"
            class="w-full h-full object-cover"
          />
          <div class="absolute inset-0 bg-gradient-to-t from-black/60 via-transparent to-transparent opacity-0 group-hover:opacity-100 transition-opacity">
            <div class="absolute bottom-2 left-2 right-2">
              <div class="text-xs text-white/80 truncate">@{@item.user_name}</div>
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
          
          <div class="mt-2 pt-2 border-t border-white/5">
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
