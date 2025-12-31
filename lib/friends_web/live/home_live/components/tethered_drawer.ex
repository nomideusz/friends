defmodule FriendsWeb.HomeLive.Components.TetheredDrawer do
  @moduledoc """
  Tethered Drawer component that slides from screen edges with a visual
  tether line connecting to the avatar. Creates the feeling of the avatar
  "pulling out" content.
  """
  use FriendsWeb, :html

  # ============================================================================
  # TETHERED DRAWER
  # Edge-anchored drawer with visual tether to avatar
  # ============================================================================

  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :avatar_position, :string, default: "top-right"
  attr :close_event, :string, required: true
  attr :title, :string, default: nil
  slot :inner_block, required: true

  def tethered_drawer(assigns) do
    # Determine drawer positioning based on avatar position
    {drawer_side, drawer_classes, tether_classes} = drawer_positioning(assigns.avatar_position)
    
    assigns = assigns
      |> assign(:drawer_side, drawer_side)
      |> assign(:drawer_classes, drawer_classes)
      |> assign(:tether_classes, tether_classes)

    ~H"""
    <%= if @show do %>
      <div
        id={@id}
        class="fixed inset-0 z-[300]"
        phx-hook="LockScroll"
        phx-window-keydown={@close_event}
        phx-key="escape"
      >
        <%!-- Backdrop --%>
        <div
          class="absolute inset-0 bg-black/60 backdrop-blur-sm animate-in fade-in duration-200"
          phx-click={@close_event}
        ></div>

        <%!-- Tether Line SVG --%>
        <svg
          class="absolute inset-0 z-[301] pointer-events-none overflow-visible"
          phx-hook="TetheredLine"
          id={"#{@id}-tether"}
          data-avatar-position={@avatar_position}
          data-drawer-id={"#{@id}-content"}
        >
          <defs>
            <linearGradient id={"#{@id}-tether-gradient"} x1="0%" y1="0%" x2="100%" y2="0%">
              <stop offset="0%" stop-color="white" stop-opacity="0.6" />
              <stop offset="50%" stop-color="white" stop-opacity="0.3" />
              <stop offset="100%" stop-color="white" stop-opacity="0.1" />
            </linearGradient>
            <filter id={"#{@id}-glow"}>
              <feGaussianBlur stdDeviation="2" result="coloredBlur"/>
              <feMerge>
                <feMergeNode in="coloredBlur"/>
                <feMergeNode in="SourceGraphic"/>
              </feMerge>
            </filter>
          </defs>
          <%!-- The line will be drawn by JS hook --%>
          <line
            id={"#{@id}-tether-line"}
            stroke={"url(##{@id}-tether-gradient)"}
            stroke-width="2"
            filter={"url(##{@id}-glow)"}
            class="tether-line"
          />
        </svg>

        <%!-- Drawer Panel --%>
        <div
          id={"#{@id}-content"}
          class={[
            "fixed z-[302] flex flex-col",
            "bg-neutral-900/95 backdrop-blur-xl",
            "border-white/10 shadow-2xl",
            "transition-transform duration-300 ease-out",
            @drawer_classes
          ]}
          phx-click-away={@close_event}
        >
          <%!-- Drawer Header --%>
          <div class="flex items-center justify-between px-4 py-3 border-b border-white/10">
            <%= if @title do %>
              <h2 class="text-lg font-semibold text-white"><%= @title %></h2>
            <% else %>
              <div></div>
            <% end %>
            
            <button
              type="button"
              phx-click={@close_event}
              class="w-8 h-8 rounded-lg bg-white/5 hover:bg-white/10 flex items-center justify-center text-white/60 hover:text-white transition-colors cursor-pointer"
            >
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>

          <%!-- Drawer Content --%>
          <div class="flex-1 overflow-y-auto">
            <%= render_slot(@inner_block) %>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  # ============================================================================
  # POSITIONING HELPER
  # Determines drawer side and classes based on avatar position
  # ============================================================================

  defp drawer_positioning(avatar_position) do
    case avatar_position do
      "top-left" ->
        {
          :left,
          "left-0 top-0 bottom-0 w-80 max-w-[85vw] border-r rounded-r-2xl animate-in slide-in-from-left duration-300",
          "left"
        }
      "bottom-left" ->
        {
          :left,
          "left-0 top-0 bottom-0 w-80 max-w-[85vw] border-r rounded-r-2xl animate-in slide-in-from-left duration-300",
          "left"
        }
      "top-right" ->
        {
          :right,
          "right-0 top-0 bottom-0 w-80 max-w-[85vw] border-l rounded-l-2xl animate-in slide-in-from-right duration-300",
          "right"
        }
      "bottom-right" ->
        {
          :right,
          "right-0 top-0 bottom-0 w-80 max-w-[85vw] border-l rounded-l-2xl animate-in slide-in-from-right duration-300",
          "right"
        }
      _ ->
        # Default: right side
        {
          :right,
          "right-0 top-0 bottom-0 w-80 max-w-[85vw] border-l rounded-l-2xl animate-in slide-in-from-right duration-300",
          "right"
        }
    end
  end
end
