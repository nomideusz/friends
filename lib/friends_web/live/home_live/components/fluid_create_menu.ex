defmodule FriendsWeb.HomeLive.Components.FluidCreateMenu do
  @moduledoc """
  Fluid create menu with Apple-like monochrome design.
  Options appear above the bottom toolbar.
  """
  use FriendsWeb, :html

  # ============================================================================
  # FLUID CREATE MENU
  # Minimal monochrome menu for content creation
  # ============================================================================

  attr :show, :boolean, default: false
  attr :context, :atom, default: :feed
  attr :uploads, :any, default: nil

  def fluid_create_menu(assigns) do
    # Determine which upload key to use based on context
    upload_key = if assigns.context == :room, do: :photo, else: :feed_photo
    has_upload = assigns.uploads && assigns.uploads[upload_key]
    
    assigns = assigns
      |> assign(:upload_key, upload_key)
      |> assign(:has_upload, has_upload)
      |> assign(:upload, if(has_upload, do: assigns.uploads[upload_key], else: nil))

    ~H"""
    <%= if @show do %>
      <%!-- Invisible backdrop for click-to-close --%>
      <div
        id="create-menu-backdrop"
        class="fixed inset-0 z-[149]"
        phx-click="close_create_menu"
      ></div>

      <%!-- Menu Container - positioned above nav bar --%>
      <div
        id="create-menu"
        class="fixed bottom-22 left-1/2 -translate-x-1/2 z-[150] w-72 animate-in zoom-in-95 fade-in duration-200"
      >
        <%!-- Container matching nav bar styling --%>
        <div class="bg-neutral-900/95 backdrop-blur-xl border border-white/10 rounded-2xl overflow-hidden shadow-2xl">
          <%!-- Photo - uses label to directly trigger file input --%>
          <form id="create-menu-upload-form" phx-change="validate" phx-submit="save" class="contents">
            <label 
              id="photo-upload-label"
              phx-hook="PhotoUploadLabel"
              class="w-full flex items-center gap-3 px-4 py-3 hover:bg-white/5 transition-colors cursor-pointer group"
            >
              <div class="w-8 h-8 rounded-full bg-white/10 flex items-center justify-center flex-shrink-0 group-hover:bg-white/15 transition-colors">
                <.create_icon name="camera" />
              </div>
              <span class="text-sm font-medium text-white/90 group-hover:text-white transition-colors">
                Photo
              </span>
              <%= if @has_upload do %>
                <.live_file_input upload={@upload} class="sr-only" />
              <% end %>
            </label>
          </form>

          <%!-- Voice - only show in feed context --%>
          <%= if @context != :room do %>
            <div class="border-t border-white/10"></div>
            <button
              type="button"
              id="create-menu-voice-btn"
              phx-hook="FeedVoiceRecorder"
              phx-click="start_voice_recording"
              class="w-full flex items-center gap-3 px-4 py-3 hover:bg-white/5 transition-colors cursor-pointer group"
            >
              <div class="w-8 h-8 rounded-full bg-white/10 flex items-center justify-center flex-shrink-0 group-hover:bg-white/15 transition-colors">
                <.create_icon name="mic" />
              </div>
              <span class="text-sm font-medium text-white/90 group-hover:text-white transition-colors">
                Voice
              </span>
            </button>
          <% end %>

          <%!-- Note --%>
          <div class="border-t border-white/10"></div>
          <.create_option icon="note" label="Note" event="open_note_modal" />
        </div>
      </div>
    <% end %>
    """
  end

  # ============================================================================
  # CREATE OPTION
  # Row-based option matching Settings sheet design
  # ============================================================================

  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :event, :string, required: true

  defp create_option(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={@event}
      class="w-full flex items-center gap-3 px-4 py-3 hover:bg-white/5 transition-colors cursor-pointer group"
    >
      <div class="w-8 h-8 rounded-full bg-white/10 flex items-center justify-center flex-shrink-0 group-hover:bg-white/15 transition-colors">
        <.create_icon name={@icon} />
      </div>
      <span class="text-sm font-medium text-white/90 group-hover:text-white transition-colors">
        {@label}
      </span>
    </button>
    """
  end

  # ============================================================================
  # ICONS
  # ============================================================================

  attr :name, :string, required: true

  defp create_icon(%{name: "camera"} = assigns) do
    ~H"""
    <svg class="w-5 h-5 text-white/70" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M3 9a2 2 0 012-2h.93a2 2 0 001.664-.89l.812-1.22A2 2 0 0110.07 4h3.86a2 2 0 011.664.89l.812 1.22A2 2 0 0018.07 7H19a2 2 0 012 2v9a2 2 0 01-2 2H5a2 2 0 01-2-2V9z" />
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M15 13a3 3 0 11-6 0 3 3 0 016 0z" />
    </svg>
    """
  end

  defp create_icon(%{name: "mic"} = assigns) do
    ~H"""
    <svg class="w-5 h-5 text-white/70" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z" />
    </svg>
    """
  end

  defp create_icon(%{name: "note"} = assigns) do
    ~H"""
    <svg class="w-5 h-5 text-white/70" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
    </svg>
    """
  end

  defp create_icon(assigns) do
    ~H"""
    <svg class="w-5 h-5 text-white/70" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M12 4v16m8-8H4" />
    </svg>
    """
  end
end
