defmodule FriendsWeb.HomeLive.Components.FluidUploadIndicator do
  @moduledoc """
  A fluid, liquid-style upload progress indicator for the New Internet aesthetic.
  Features a pulsing orb with animated liquid fill and glassmorphism styling.
  """
  use Phoenix.Component

  @doc """
  Renders the upload indicator when uploads are in progress.
  
  ## Attributes
    * `uploading` - Boolean indicating if an upload is in progress
    * `entries` - List of upload entries to calculate progress
  """
  attr :uploading, :boolean, default: false
  attr :entries, :list, default: []

  def upload_indicator(assigns) do
    # Calculate overall progress from entries
    progress = calculate_progress(assigns.entries)
    entry_count = length(assigns.entries)
    
    assigns = assign(assigns, :progress, progress)
    assigns = assign(assigns, :entry_count, entry_count)

    ~H"""
    <%= if @uploading do %>
      <div class="fixed bottom-24 left-1/2 -translate-x-1/2 z-[200] animate-in fade-in zoom-in-95 duration-300">
        <%!-- Glassmorphism container --%>
        <div class="relative flex items-center gap-3 px-4 py-2.5 bg-black/60 backdrop-blur-xl border border-white/10 rounded-full shadow-2xl">
          
          <%!-- Pulsing orb with liquid fill --%>
          <div class="relative w-8 h-8">
            <%!-- Outer glow ring --%>
            <div class="absolute inset-0 rounded-full bg-gradient-to-r from-violet-500/30 to-blue-500/30 animate-pulse"></div>
            
            <%!-- Main orb container --%>
            <div class="absolute inset-0.5 rounded-full bg-neutral-900/80 border border-white/10 overflow-hidden">
              <%!-- Liquid fill --%>
              <div 
                class="absolute bottom-0 left-0 right-0 bg-gradient-to-t from-violet-500 via-violet-400 to-blue-400 transition-all duration-300 ease-out"
                style={"height: #{@progress}%;"}
              >
                <%!-- Liquid surface wave effect --%>
                <div class="absolute top-0 left-0 right-0 h-1.5 bg-gradient-to-r from-transparent via-white/40 to-transparent animate-wave"></div>
              </div>
              
              <%!-- Shimmer overlay --%>
              <div class="absolute inset-0 bg-gradient-to-br from-white/10 via-transparent to-transparent"></div>
            </div>
            
            <%!-- Orbiting dot (subtle activity indicator) --%>
            <div class="absolute inset-0 animate-spin-slow">
              <div class="absolute top-0 left-1/2 -translate-x-1/2 -translate-y-0.5 w-1 h-1 rounded-full bg-white/60"></div>
            </div>
          </div>
          
          <%!-- Status text --%>
          <div class="flex flex-col">
            <span class="text-xs font-medium text-white/90">
              <%= if @progress >= 100 do %>
                Processing...
              <% else %>
                Uploading<%= if @entry_count > 1, do: " #{@entry_count} files", else: "" %>
              <% end %>
            </span>
            <span class="text-[10px] text-white/50">
              <%= @progress %>%
            </span>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  defp calculate_progress([]), do: 0
  defp calculate_progress(entries) do
    total = length(entries)
    sum = Enum.reduce(entries, 0, fn entry, acc -> acc + entry.progress end)
    round(sum / total)
  end
end
