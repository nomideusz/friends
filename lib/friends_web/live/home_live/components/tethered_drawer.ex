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
  attr :close_event, :string, required: true
  attr :title, :string, default: nil
  slot :inner_block, required: true

  def tethered_drawer(assigns) do
    # Fixed to right side (matching avatar in top-right)
    assigns = assigns
      |> assign(:drawer_side, :right)
      |> assign(:drawer_classes, "right-0 top-0 bottom-0 max-w-[85vw] border-l rounded-l-2xl drawer-spring-in-right")

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
          data-avatar-position="top-right"
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
          phx-hook="ResizableDrawer"
          data-side={@drawer_side}
          class={[
            "fixed z-[302] flex flex-col drawer-resizable",
            "bg-black/70 backdrop-blur-2xl saturate-150",
            "border-white/10 shadow-[0_0_60px_-15px_rgba(0,0,0,0.8)]",
            @drawer_classes
          ]}
          phx-click-away={@close_event}
        >
          <%!-- Resize Handle --%>
          <div class={"drawer-resize-handle " <> if @drawer_side == :right, do: "drawer-resize-handle-left", else: "drawer-resize-handle-right"}></div>
          
          <%!-- Drawer Header --%>
          <div class="flex items-center justify-between px-5 py-4 border-b border-white/10">
            <%= if @title do %>
              <h2 class="text-lg font-bold text-white tracking-tight"><%= @title %></h2>
            <% else %>
              <div></div>
            <% end %>
            
            <button
              type="button"
              phx-click={@close_event}
              class="w-9 h-9 rounded-xl bg-white/5 hover:bg-white/10 flex items-center justify-center text-white/50 hover:text-white transition-all cursor-pointer"
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
end
