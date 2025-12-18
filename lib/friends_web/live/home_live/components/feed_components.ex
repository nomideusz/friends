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
    <%= if @uploads && @uploads[:feed_photo] && @uploads.feed_photo.entries != [] do %>
      <% 
        entries = @uploads.feed_photo.entries
        count = length(entries)
        avg_progress = div(Enum.reduce(entries, 0, & &1.progress + &2), count)
      %>
      <div class="mb-4 aether-card p-3 animate-in fade-in slide-in-from-top-2 duration-300 pointer-events-auto">
        <div class="flex items-center gap-4">
          <div class="w-10 h-10 rounded-full bg-blue-500/10 flex items-center justify-center shrink-0 border border-blue-500/20">
            <svg class="w-5 h-5 text-blue-400 animate-pulse" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-8l-4-4m0 0L8 8m4-4v12" />
            </svg>
          </div>
          
          <div class="flex-1 min-w-0">
             <div class="flex justify-between items-end mb-1.5">
               <span class="text-xs font-bold text-neutral-300 uppercase tracking-wider">
                 Uploading <%= count %> <%= if count == 1, do: "photo", else: "photos" %>...
               </span>
               <span class="text-xs font-mono font-bold text-blue-400"><%= avg_progress %>%</span>
             </div>
             
             <div class="h-1.5 bg-neutral-800 rounded-full overflow-hidden">
               <div 
                 class="h-full bg-blue-500 transition-all duration-300 ease-out shadow-[0_0_8px_rgba(59,130,246,0.6)]" 
                 style={"width: #{avg_progress}%"}
               ></div>
             </div>
          </div>
          
          <%= if count == 1 do %>
             <button
               type="button"
               phx-click="cancel_upload"
               phx-value-ref={hd(entries).ref}
               class="text-neutral-500 hover:text-white p-2 hover:bg-white/5 rounded-lg transition-colors cursor-pointer"
               title="Cancel upload"
             >
               <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                 <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
               </svg>
             </button>
          <% end %>
        </div>
      </div>
    <% end %>
    """
  end

  # Delegate to shared CardComponents


  def feed_actions_bar(assigns) do
    assigns = assign(assigns, :upload_key, :feed_photo)
    ~H"""
    <div>
      <%!-- Photo Input (Allows CornerNav trigger) --%>
      <%= if @uploads && @uploads[@upload_key] do %>
        <form
          id="upload-form-feed_photo"
          phx-change="validate_feed_photo"
          phx-submit="save_feed_photo"
          class="hidden"
        >
          <%!-- IMPORTANT: ID must match CornerNavigation fallback selector --%>
          <.live_file_input upload={@uploads[@upload_key]} class="sr-only" id="feed_upload_input" />
        </form>
      <% end %>

      <%!-- Voice Recorder (Visible ONLY when recording) --%>
      <button
        type="button"
        id="feed-voice-record"
        phx-hook="FeedVoiceRecorder"
        class={"#{if @recording_voice, do: "w-full mb-4 py-3 bg-red-500/10 border border-red-500 text-red-500 rounded-lg animate-pulse font-bold flex items-center justify-center gap-2 pointer-events-auto", else: "hidden"}"}
      >
         <svg class="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
           <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z" />
         </svg>
         <span>Recording... (Tap to Stop)</span>
      </button>
    </div>
    """
  end

  attr :welcome_graph_data, :map, default: nil
  attr :current_user_id, :any, default: nil

  def empty_feed(assigns) do
    ~H"""
    <%= if @welcome_graph_data do %>
      <%!-- Live network graph for new users --%>
      <div id="empty-feed-graph" class="fixed inset-0 z-0" phx-update="ignore">
        <div
          id="welcome-graph"
          phx-hook="WelcomeGraph"
          class="w-full h-full"
          data-graph-data={Jason.encode!(@welcome_graph_data)}
          data-current-user-id={@current_user_id}
          data-always-show="true">
        </div>
      </div>
    <% else %>
      <%!-- Pure void when no graph data --%>
      <div id="empty-feed-container" class="min-h-[60vh]"></div>
    <% end %>
    """
  end

  attr :feed_items, :list, required: true

  def feed_grid(assigns) do
    ~H"""
    <div
      id="public-feed-grid"
      phx-update="stream"
      phx-hook="PhotoGrid"
      class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-3 xl:grid-cols-4 gap-4 pointer-events-auto"
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
    <%= if Map.get(@item, :type) == :gallery do %>
      <%!-- Gallery item (multiple photos batch) --%>
      <div
        id={@id}
        class="photo-item aether-card group relative aspect-square overflow-hidden cursor-pointer animate-in fade-in zoom-in-95 duration-300"
        phx-click="view_gallery"
        phx-value-batch_id={@item.batch_id}
      >
        <img
          src={get_in(@item, [:first_photo, :thumbnail_data]) || get_in(@item, [:first_photo, :image_data])}
          alt="Photo gallery"
          class="w-full h-full object-cover ease-out"
        />

        <%!-- Gallery count indicator --%>
        <div class="absolute top-3 right-3 px-2.5 py-1 rounded-full bg-black/60 backdrop-blur-sm border border-white/20">
          <div class="flex items-center gap-1.5">
            <svg class="w-3.5 h-3.5 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
            </svg>
            <span class="text-xs font-bold text-white"><%= @item.photo_count %></span>
          </div>
        </div>

        <%!-- User info overlay --%>
        <div class="absolute inset-x-0 bottom-0 p-4 bg-gradient-to-t from-black/80 via-black/20 to-transparent opacity-0 group-hover:opacity-100 transition-opacity duration-300">
          <div class="text-[10px] font-bold text-white/70 uppercase tracking-wider">@<%= @item.user_name || "unknown" %></div>
        </div>
      </div>
    <% else %>
      <%= if @item.type == :photo or @item.type == "photo" do %>
        <div
          id={@id}
          class="photo-item aether-card group relative aspect-square overflow-hidden cursor-pointer animate-in fade-in zoom-in-95 duration-300"
          phx-click="view_feed_photo"
          phx-value-photo_id={@item.id}
        >
          <%= if is_binary(@item[:content_type]) && String.starts_with?(@item.content_type, "audio/") do %>
            <div class="w-full h-full flex flex-col items-center justify-center p-4 text-center relative overflow-hidden bg-gradient-to-br from-orange-500/10 to-amber-900/40" onclick="event.stopPropagation();">
              <!-- Decorative wave background -->
              <!-- Real Waveform Visualization -->
              <canvas
                id={"waveform-#{@item.id}"}
                phx-hook="VoiceWaveform"
                data-src={@item.image_data}
                class="absolute inset-x-0 bottom-0 w-full h-[60%] text-orange-400 opacity-80"
                width="200"
                height="80"
                onclick="event.stopPropagation();"
              ></canvas>
              
              <div class="relative z-10 flex flex-col items-center w-full">
                <div class="w-12 h-12 rounded-full bg-orange-500/20 flex items-center justify-center mb-3 border border-orange-500/30 group-hover:scale-110 transition-transform duration-300 shadow-[0_0_15px_rgba(249,115,22,0.3)]">
                  <svg class="w-6 h-6 text-orange-200" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z" />
                  </svg>
                </div>
                
                <span class="text-[10px] font-bold text-orange-200/50 uppercase tracking-widest mb-3">Voice Note</span>
                
                <audio controls src={@item.image_data} class="w-full h-7 max-w-[140px] opacity-90 transition-opacity invert hue-rotate-15" style="transform: scale(0.9);" onclick="event.stopPropagation();" />
                
                <div class="mt-4 flex items-center gap-2 px-3 py-1 rounded-full bg-orange-950/30 border border-orange-500/20 shadow-sm">
                  <div class="w-1.5 h-1.5 rounded-full bg-orange-500 animate-pulse shadow-[0_0_5px_orange]"></div>
                  <span class="text-[10px] text-orange-200/60 font-bold uppercase tracking-tight">@<%= @item.user_name || "unknown" %></span>
                </div>
              </div>
            </div>
          <% else %>
            <img
              src={@item.thumbnail_data || @item[:image_data]}
              alt="Feed photo"
              class="w-full h-full object-cover ease-out"
            />
            <div class="absolute inset-x-0 bottom-0 p-4 bg-gradient-to-t from-black/80 via-black/20 to-transparent opacity-0 group-hover:opacity-100 transition-opacity duration-300">
              <div class="text-[10px] font-bold text-white/70 uppercase tracking-wider">@<%= @item.user_name || "unknown" %></div>
            </div>
          <% end %>
        </div>
      <% else %>
        <%!-- Note item (Minimalist) --%>
        <div
          id={@id}
          class="note-item group relative aspect-square overflow-hidden cursor-pointer animate-in fade-in zoom-in-95 duration-300 rounded-[2rem] border border-white/5 bg-white/[0.02] hover:bg-white/[0.04] transition-colors"
          phx-click="view_feed_note"
          phx-value-note_id={@item.id}
        >
          <div class="w-full h-full p-6 flex flex-col justify-between">
            <div class="flex-1 overflow-hidden flex flex-col justify-center">
              <p class="text-sm sm:text-base text-white/80 font-normal leading-relaxed line-clamp-6 font-display tracking-wide italic"><%= @item.content || "" %></p>
            </div>
            
            <div class="mt-2 pt-4 border-t border-white/5">
              <div class="flex items-center gap-2 opacity-60 group-hover:opacity-100 transition-opacity">
                <div
                  class="w-4 h-4 rounded-full"
                  style={"background-color: #{@item.user_color || "#888"}"}
                >
                </div>
                 <span class="text-[9px] font-bold text-white/30 uppercase tracking-widest truncate">@<%= @item.user_name || "unknown" %></span>
              </div>
            </div>
          </div>
        </div>
      <% end %>
    <% end %>
    """
  end
end
