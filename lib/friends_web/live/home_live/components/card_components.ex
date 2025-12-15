defmodule FriendsWeb.HomeLive.Components.CardComponents do
  @moduledoc """
  Shared card components used in both feed and room views.
  Provides consistent styling and behavior for photo, note, and voice cards.
  """
  use Phoenix.Component
  alias Phoenix.LiveView.JS

  # --- Photo Card ---

  attr :id, :string, required: true
  attr :thumbnail_src, :string, required: true
  attr :user_name, :string, default: "unknown"
  attr :user_color, :string, default: "#888"
  attr :on_click, :string, default: nil
  attr :click_value, :map, default: %{}
  attr :show_delete, :boolean, default: false
  attr :delete_event, :string, default: "delete_photo"
  attr :delete_id, :any, default: nil

  def photo_card(assigns) do
    ~H"""
    <div
      id={@id}
      class="photo-item aether-card group relative aspect-square overflow-hidden cursor-pointer transition-all hover:-translate-y-1 animate-in fade-in zoom-in-95 duration-300"
      phx-click={@on_click}
      {Map.to_list(@click_value)}
    >
      <img
        src={@thumbnail_src}
        alt="Photo"
        class="w-full h-full object-cover"
      />
      <div class="absolute inset-0 bg-gradient-to-t from-black/60 via-transparent to-transparent opacity-0 group-hover:opacity-100 transition-opacity">
        <div class="absolute bottom-2 left-2 right-2">
          <div class="text-xs font-bold text-neutral-500 truncate">@{@user_name}</div>
        </div>
      </div>
      
      <%= if @show_delete do %>
        <button
          type="button"
          phx-click={@delete_event}
          phx-value-id={@delete_id}
          data-confirm="delete?"
          class="absolute top-2 right-2 text-neutral-500 hover:text-red-500 text-xs cursor-pointer opacity-0 group-hover:opacity-100 transition-opacity"
        >
          delete
        </button>
      <% end %>
    </div>
    """
  end

  # --- Note Card ---

  attr :id, :string, required: true
  attr :content, :string, required: true
  attr :user_name, :string, default: "unknown"
  attr :user_color, :string, default: "#888"
  attr :on_click, :string, default: nil
  attr :click_value, :map, default: %{}
  attr :show_delete, :boolean, default: false
  attr :delete_event, :string, default: "delete_note"
  attr :delete_id, :any, default: nil

  def note_card(assigns) do
    ~H"""
    <div
      id={@id}
      class="note-item aether-card group relative aspect-square overflow-hidden cursor-pointer transition-all hover:-translate-y-1 animate-in fade-in zoom-in-95 duration-300"
      phx-click={@on_click}
      {Map.to_list(@click_value)}
    >
      <div class="w-full h-full p-4 flex flex-col">
        <div class="flex-1 overflow-hidden">
          <p class="text-sm text-neutral-200 line-clamp-6">{@content}</p>
        </div>
        
        <div class="mt-2 pt-2 border-t border-neutral-200">
          <div class="flex items-center gap-2">
            <div
              class="w-5 h-5 rounded-full"
              style={"background-color: #{@user_color}"}
            >
            </div>
             <span class="text-xs text-neutral-500 truncate">@{@user_name}</span>
          </div>
        </div>
      </div>

      <%= if @show_delete do %>
        <button
          type="button"
          phx-click={@delete_event}
          phx-value-id={@delete_id}
          data-confirm="delete?"
          class="absolute top-2 right-2 text-neutral-500 hover:text-red-500 transition-colors opacity-0 group-hover:opacity-100 p-2 z-10"
          phx-click-stop
        >
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
          </svg>
        </button>
      <% end %>
    </div>
    """
  end

  # --- Voice Card (Feed style - uses audio element) ---

  attr :id, :string, required: true
  attr :audio_src, :string, required: true
  attr :user_name, :string, default: "unknown"

  def voice_card_feed(assigns) do
    ~H"""
    <div
      id={@id}
      class="photo-item aether-card group relative aspect-square overflow-hidden cursor-pointer transition-all hover:-translate-y-1 animate-in fade-in zoom-in-95 duration-300"
    >
      <div class="w-full h-full flex flex-col items-center justify-center p-3 sm:p-4 text-center relative overflow-hidden" onclick="event.stopPropagation();">
        <div class="relative z-10 flex flex-col items-center w-full">
          <div class="w-10 h-10 sm:w-12 sm:h-12 rounded-full bg-white/10 flex items-center justify-center mb-2 sm:mb-3 ring-1 ring-white/20 group-hover:scale-110 transition-transform duration-300">
            <svg class="w-5 h-5 sm:w-6 sm:h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z" />
            </svg>
          </div>
          
          <span class="text-[10px] font-medium text-neutral-400 uppercase tracking-widest mb-2">Voice Note</span>
          
          <audio controls src={@audio_src} class="w-full h-6 sm:h-7 max-w-[120px] sm:max-w-[140px] opacity-90 hover:opacity-100 transition-opacity" style="transform: scale(0.85);" onclick="event.stopPropagation();" />
          
          <div class="mt-2 flex items-center gap-1 px-2 py-0.5 rounded-full bg-neutral-900 border border-white/10 shadow-sm">
            <div class="w-2 h-2 rounded-full bg-blue-500 animate-pulse"></div>
            <span class="text-[10px] text-neutral-400 font-medium">@{@user_name}</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # --- Voice Card (Room style - uses hook for decryption) ---

  attr :id, :string, required: true
  attr :item_id, :any, required: true
  attr :room_id, :any, required: true
  attr :encrypted_data, :string, required: true
  attr :nonce, :string, required: true
  attr :user_name, :string, default: "unknown"

  def voice_card_room(assigns) do
    ~H"""
    <div
      id={@id}
      class="photo-item aether-card group relative aspect-square overflow-hidden cursor-pointer transition-all hover:-translate-y-1 animate-in fade-in zoom-in-95 duration-300"
    >
      <div
        class="w-full h-full flex flex-col items-center justify-center p-3 sm:p-4 text-center relative z-10"
        id={"grid-voice-player-#{@item_id}"}
        data-item-id={@item_id}
        data-room-id={@room_id}
        phx-hook="GridVoicePlayer"
      >
        <div
          class="hidden"
          id={"grid-voice-data-#{@item_id}"}
          data-encrypted={@encrypted_data}
          data-nonce={@nonce}
        >
        </div>
        
        <div class="relative z-10 flex flex-col items-center w-full">
          <div class="w-10 h-10 sm:w-12 sm:h-12 rounded-full bg-white/10 flex items-center justify-center mb-2 sm:mb-3 ring-1 ring-white/20">
            <svg class="w-5 h-5 sm:w-6 sm:h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z" />
            </svg>
          </div>
          
          <span class="text-[10px] font-medium text-neutral-400 uppercase tracking-widest mb-2">Voice Note</span>
          
          <button class="grid-voice-play-btn w-10 h-10 rounded-full bg-white/10 hover:bg-white/20 border border-white/20 hover:border-white/40 flex items-center justify-center text-white transition-all group-hover:scale-110 active:scale-95 cursor-pointer z-20 mb-2">
            <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
              <path d="M8 5v14l11-7z" />
            </svg>
          </button>
          
          <div class="w-full max-w-[120px] h-1.5 bg-neutral-900/50 rounded-full overflow-hidden border border-white/5">
            <div class="grid-voice-progress h-full bg-blue-500 w-0 transition-all"></div>
          </div>
          
          <div class="mt-2 flex items-center gap-1 px-2 py-0.5 rounded-full bg-neutral-900 border border-white/10 shadow-sm">
            <div class="w-2 h-2 rounded-full bg-blue-500 animate-pulse"></div>
            <span class="text-[10px] text-neutral-400 font-medium">@{@user_name}</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # --- Action Button ---

  attr :icon, :atom, required: true, values: [:photo, :note, :voice]
  attr :label, :string, required: true
  attr :on_click, :string, default: nil
  attr :is_active, :boolean, default: false
  attr :for_upload, :string, default: nil
  slot :inner_block

  def action_button(assigns) do
    ~H"""
    <%= if @for_upload do %>
      <label
        for={@for_upload}
        class="flex-1 flex flex-col items-center justify-center gap-1 py-2 sm:py-3 px-2 sm:px-4 rounded-lg btn-aether cursor-pointer group"
      >
        <.action_icon icon={@icon} is_active={@is_active} />
        <span class="text-[10px] sm:text-xs font-bold uppercase tracking-wider text-neutral-500 group-hover:text-white">
          {@label}
        </span>
        {render_slot(@inner_block)}
      </label>
    <% else %>
      <button
        type="button"
        phx-click={@on_click}
        class={"flex-1 flex flex-col items-center justify-center gap-1 py-2 sm:py-3 px-2 sm:px-4 rounded-lg btn-aether cursor-pointer group #{if @is_active, do: "border-blue-500 shadow-[0_0_10px_rgba(59,130,246,0.3)]", else: ""}"}
      >
        <.action_icon icon={@icon} is_active={@is_active} />
        <span class={"text-[10px] sm:text-xs font-bold uppercase tracking-wider #{if @is_active, do: "text-blue-400", else: "text-neutral-500 group-hover:text-white"}"}>
          {@label}
        </span>
        {render_slot(@inner_block)}
      </button>
    <% end %>
    """
  end

  # --- Action Icon Helper ---

  attr :icon, :atom, required: true
  attr :is_active, :boolean, default: false

  defp action_icon(assigns) do
    ~H"""
    <%= case @icon do %>
      <% :photo -> %>
        <svg class="w-5 h-5 sm:w-6 sm:h-6 text-neutral-400 group-hover:text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 9a2 2 0 012-2h.93a2 2 0 001.664-.89l.812-1.22A2 2 0 0110.07 4h3.86a2 2 0 011.664.89l.812 1.22A2 2 0 0018.07 7H19a2 2 0 012 2v9a2 2 0 01-2 2H5a2 2 0 01-2-2V9z" />
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 13a3 3 0 11-6 0 3 3 0 016 0z" />
        </svg>
      <% :note -> %>
        <svg class="w-5 h-5 sm:w-6 sm:h-6 text-neutral-400 group-hover:text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
        </svg>
      <% :voice -> %>
        <svg class={"w-5 h-5 sm:w-6 sm:h-6 #{if @is_active, do: "text-blue-400 animate-pulse", else: "text-neutral-400 group-hover:text-white"}"} fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z" />
        </svg>
    <% end %>
    """
  end

  # --- Actions Bar ---

  attr :uploads, :map, default: nil
  attr :uploading, :boolean, default: false
  attr :recording_voice, :boolean, default: false
  attr :note_event, :string, default: "open_feed_note_modal"
  attr :voice_button_id, :string, default: "feed-voice-record"
  attr :voice_hook, :string, default: "FeedVoiceRecorder"
  attr :room_id, :any, default: nil
  attr :upload_key, :atom, default: :feed_photo
  attr :id_prefix, :string, default: nil
  attr :skip_file_input, :boolean, default: false

  def actions_bar(assigns) do
    ~H"""
    <div class="mb-6 flex items-stretch gap-2 sm:gap-3">
      <%!-- Photo Upload --%>
      <%= if @uploads && @uploads[@upload_key] do %>
      <form
          id={if @id_prefix, do: "#{@id_prefix}-upload-form-#{@upload_key}", else: "upload-form-#{@upload_key}"}
          phx-change={if @upload_key == :feed_photo, do: "validate_feed_photo", else: "validate"}
          phx-submit={if @upload_key == :feed_photo, do: "save_feed_photo", else: "save"}
          class="contents"
        >
          <.action_button icon={:photo} label={if @uploading, do: "...", else: "Photo"} for_upload={@uploads[@upload_key].ref}>
            <%= unless @skip_file_input do %>
              <.live_file_input upload={@uploads[@upload_key]} class="sr-only" />
            <% end %>
          </.action_button>
        </form>
      <% end %>
      
      <%!-- Note Button --%>
      <.action_button icon={:note} label="Note" on_click={@note_event} />
      
      <%!-- Voice Button --%>
      <button
        type="button"
        id={@voice_button_id}
        phx-hook={@voice_hook}
        data-room-id={@room_id}
        class={"flex-1 flex flex-col items-center justify-center gap-1 py-2 sm:py-3 px-2 sm:px-4 rounded-lg btn-aether cursor-pointer group #{if @recording_voice, do: "border-blue-500 shadow-[0_0_10px_rgba(59,130,246,0.3)]", else: ""}"}
      >
        <svg class={"w-5 h-5 sm:w-6 sm:h-6 #{if @recording_voice, do: "text-blue-400 animate-pulse", else: "text-neutral-400 group-hover:text-white"}"} fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z" />
        </svg>
        <span class={"text-[10px] sm:text-xs font-bold uppercase tracking-wider #{if @recording_voice, do: "text-blue-400", else: "text-neutral-500 group-hover:text-white"}"}>
          {if @recording_voice, do: "Rec", else: "Voice"}
        </span>
      </button>
    </div>
    """
  end
end
