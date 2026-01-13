defmodule FriendsWeb.HomeLive.Components.FluidRoomContentComponents do
  @moduledoc """
  Content display components for private rooms.
  Includes content grid, item renderers, and empty state.
  """
  use FriendsWeb, :html
  import FriendsWeb.HomeLive.Helpers

  # ============================================================================
  # EMPTY STATE
  # Just a subtle orb, no text
  # ============================================================================

  def fluid_empty_state(assigns) do
    ~H"""
    <div class="flex items-center justify-center h-[60vh]">
      <div class="w-16 h-16 rounded-full bg-white/5 border border-white/10 flex items-center justify-center animate-pulse">
        <div class="w-3 h-3 rounded-full bg-white/20"></div>
      </div>
    </div>
    """
  end

  # ============================================================================
  # CONTENT GRID
  # Full-width masonry-style grid
  # ============================================================================

  attr :items, :list, required: true
  attr :room, :map, required: true
  attr :current_user, :map, required: true

  def fluid_content_grid(assigns) do
    # Check if current user is admin
    is_admin = Friends.Social.is_admin?(assigns.current_user)
    assigns = assign(assigns, :is_admin, is_admin)

    ~H"""
    <div
      id="fluid-items-grid"
      phx-update="stream"
      class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-1 p-1"
    >
      <%= for {dom_id, item} <- @items do %>
        <%!-- Skip audio items - they appear in the chat stream instead --%>
        <%= unless Map.get(item, :content_type) == "audio/encrypted" do %>
          <.fluid_content_item id={dom_id} item={item} room={@room} current_user={@current_user} is_admin={@is_admin} />
        <% end %>
      <% end %>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :item, :map, required: true
  attr :room, :map, required: true
  attr :current_user, :map, required: true
  attr :is_admin, :boolean, default: false

  def fluid_content_item(assigns) do
    ~H"""
    <%= case Map.get(@item, :type) do %>
      <% :gallery -> %>
        <div
          id={@id}
          class="aspect-square relative overflow-hidden cursor-pointer group"
          phx-click="view_gallery"
          phx-value-batch_id={@item.batch_id}
        >
          <img
            src={get_in(@item, [:first_photo, :thumbnail_data]) || get_in(@item, [:first_photo, :image_data])}
            alt=""
            class="w-full h-full object-cover"
            loading="lazy"
          />
          <%!-- Gallery badge --%>
          <div class="absolute top-2 right-2 flex items-center gap-1 px-2 py-1 rounded-lg bg-black/70 backdrop-blur-md border border-white/20 shadow-lg">
            <svg class="w-3.5 h-3.5 text-white/80" fill="currentColor" viewBox="0 0 24 24">
              <path d="M4 6H2v14c0 1.1.9 2 2 2h14v-2H4V6zm16-4H8c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm0 14H8V4h12v12z"/>
            </svg>
            <span class="text-xs font-semibold text-white">{@item.photo_count}</span>
          </div>
          <%!-- Hover overlay --%>
          <div class="absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100 transition-opacity"></div>
        </div>

      <% :photo -> %>
        <%= if Map.get(@item, :content_type) == "audio/encrypted" do %>
          <%!-- Voice Note (Fluid Design) --%>
          <div
            id={@id}
            class="aspect-square relative overflow-hidden bg-gradient-to-br from-purple-900/40 via-neutral-900 to-blue-900/40 flex flex-col items-center justify-center group"
            phx-hook="GridVoicePlayer"
            data-item-id={@item.id}
            data-room-id={@room.id}
          >
            <%!-- Ambient glow background --%>
            <div class="absolute inset-0 opacity-30">
              <div class="absolute top-1/4 left-1/4 w-24 h-24 rounded-full bg-purple-500/30 blur-2xl"></div>
              <div class="absolute bottom-1/4 right-1/4 w-20 h-20 rounded-full bg-blue-500/30 blur-2xl"></div>
            </div>
            
            <%!-- Hidden data element --%>
            <div class="hidden" id={"grid-voice-data-#{@item.id}"} data-encrypted={@item.image_data} data-nonce={@item.thumbnail_data}></div>
            
            <%!-- Waveform visualization bars --%>
            <div class="flex items-center gap-[3px] h-12 mb-4 z-10">
              <% heights = [35, 55, 75, 45, 85, 60, 90, 50, 70, 40, 80, 55, 65, 85, 45] %>
              <%= for height <- heights do %>
                <div 
                  class="w-[4px] rounded-full bg-gradient-to-t from-purple-400/60 to-blue-400/60 transition-all duration-300"
                  style={"height: #{height}%;"}
                ></div>
              <% end %>
            </div>
            
            <%!-- Play button with glow effect --%>
            <button class="grid-voice-play-btn relative w-14 h-14 rounded-full bg-white/10 backdrop-blur-md border border-white/20 flex items-center justify-center text-white hover:bg-white/20 hover:scale-105 transition-all cursor-pointer group-hover:shadow-[0_0_20px_rgba(168,85,247,0.4)] z-10">
              <svg class="w-6 h-6 ml-0.5" fill="currentColor" viewBox="0 0 24 24">
                <path d="M8 5v14l11-7z" />
              </svg>
            </button>
            <%!-- Delete button for owner or admin --%>
            <%= if @item.user_id == "user-#{@current_user.id}" or @item.user_id == @current_user.id or @is_admin do %>
              <button
                type="button"
                phx-click="delete_photo"
                phx-value-id={@item.id}
                data-confirm="Delete this voice message?"
                class="absolute top-2 right-2 w-6 h-6 rounded-full bg-black/60 text-white/70 hover:text-red-400 opacity-0 group-hover:opacity-100 transition-all cursor-pointer flex items-center justify-center z-20"
              >
                <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            <% end %>
          </div>
        <% else %>
          <%!-- Photo --%>
          <div
            id={@id}
            class="aspect-square relative overflow-hidden cursor-pointer group"
            phx-click="view_full_image"
            phx-value-photo_id={@item.id}
          >
            <%= if @item.thumbnail_data do %>
              <img
                src={@item.thumbnail_data}
                alt=""
                class="w-full h-full object-cover"
                loading="lazy"
              />
            <% else %>
              <div class="w-full h-full bg-neutral-800 animate-pulse"></div>
            <% end %>
            <%!-- Hover overlay --%>
            <div class="absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100 transition-opacity"></div>

            <%!-- Delete button (owner or admin) --%>
            <% is_owner = @item.user_id == "user-#{@current_user.id}" or @item.user_id == @current_user.id %>
            <%= if is_owner or @is_admin do %>
              <button
                type="button"
                phx-click="delete_photo"
                phx-value-id={@item.id}
                data-confirm="Delete?"
                class="absolute top-2 right-2 w-6 h-6 rounded-full bg-black/60 text-white/70 hover:text-red-400 opacity-0 group-hover:opacity-100 transition-all cursor-pointer flex items-center justify-center z-10"
              >
                <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            <% end %>
            
            <%!-- Pin button (owner only) --%>
            <%= if @room.owner_id == @current_user.id do %>
              <button
                type="button"
                phx-click={if Map.get(@item, :pinned_at), do: "unpin_item", else: "pin_item"}
                phx-value-type="photo"
                phx-value-id={@item.id}
                class="absolute top-2 left-2 w-6 h-6 rounded-full bg-black/60 flex items-center justify-center cursor-pointer opacity-0 group-hover:opacity-100 transition-all z-10"
                title={if Map.get(@item, :pinned_at), do: "Unpin", else: "Pin"}
              >
                <svg class={"w-3 h-3 #{if Map.get(@item, :pinned_at), do: "text-yellow-400", else: "text-white/70 hover:text-yellow-400"}"} fill={if Map.get(@item, :pinned_at), do: "currentColor", else: "none"} stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 5a2 2 0 012-2h10a2 2 0 012 2v16l-7-3.5L5 21V5z" />
                </svg>
              </button>
            <% end %>
            
            <%!-- Pinned indicator (always visible for non-owners) --%>
            <%= if Map.get(@item, :pinned_at) && @room.owner_id != @current_user.id do %>
              <div class="absolute top-2 left-2 w-5 h-5 rounded-full bg-yellow-500 flex items-center justify-center shadow-lg z-10" title="Pinned">
                <svg class="w-2.5 h-2.5 text-black" fill="currentColor" viewBox="0 0 24 24">
                  <path d="M5 5a2 2 0 012-2h10a2 2 0 012 2v16l-7-3.5L5 21V5z" />
                </svg>
              </div>
            <% end %>
          </div>
        <% end %>

      <% :note -> %>
        <%!-- Note --%>
        <div
          id={@id}
          class="aspect-square relative overflow-hidden bg-neutral-900/50 border border-white/5 cursor-pointer group p-4 flex flex-col"
          phx-click="view_full_note"
          phx-value-id={@item.id}
          phx-value-content={@item.content}
          phx-value-user={@item.user_name}
          phx-value-time={format_time(@item.inserted_at)}
        >
          <p class="text-sm text-white/80 line-clamp-5 flex-1">{@item.content}</p>
          <div class="mt-2 flex items-center gap-2">
            <div class="w-4 h-4 rounded-full" style={"background-color: #{@item.user_color || "#888"}"}></div>
            <span class="text-[10px] text-white/40">@{@item.user_name}</span>
          </div>

          <%!-- Delete button (owner or admin) --%>
          <% is_owner = @item.user_id == "user-#{@current_user.id}" or @item.user_id == @current_user.id %>
          <%= if is_owner or @is_admin do %>
            <button
              type="button"
              phx-click="delete_note"
              phx-value-id={@item.id}
              data-confirm="Delete?"
              phx-click-stop
              class="absolute top-2 right-2 w-6 h-6 rounded-full bg-black/60 text-white/70 hover:text-red-400 opacity-0 group-hover:opacity-100 transition-all cursor-pointer flex items-center justify-center z-10"
            >
              <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          <% end %>
          
          <%!-- Pin button (owner only) --%>
          <%= if @room.owner_id == @current_user.id do %>
            <button
              type="button"
              phx-click={if Map.get(@item, :pinned_at), do: "unpin_item", else: "pin_item"}
              phx-value-type="note"
              phx-value-id={@item.id}
              class="absolute top-2 left-2 w-6 h-6 rounded-full bg-black/60 flex items-center justify-center cursor-pointer opacity-0 group-hover:opacity-100 transition-all z-10"
              title={if Map.get(@item, :pinned_at), do: "Unpin", else: "Pin"}
            >
              <svg class={"w-3 h-3 #{if Map.get(@item, :pinned_at), do: "text-yellow-400", else: "text-white/70 hover:text-yellow-400"}"} fill={if Map.get(@item, :pinned_at), do: "currentColor", else: "none"} stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 5a2 2 0 012-2h10a2 2 0 012 2v16l-7-3.5L5 21V5z" />
              </svg>
            </button>
          <% end %>
          
          <%!-- Pinned indicator (always visible for non-owners) --%>
          <%= if Map.get(@item, :pinned_at) && @room.owner_id != @current_user.id do %>
            <div class="absolute top-2 left-2 w-5 h-5 rounded-full bg-yellow-500 flex items-center justify-center shadow-lg z-10" title="Pinned">
              <svg class="w-2.5 h-2.5 text-black" fill="currentColor" viewBox="0 0 24 24">
                <path d="M5 5a2 2 0 012-2h10a2 2 0 012 2v16l-7-3.5L5 21V5z" />
              </svg>
            </div>
          <% end %>
        </div>

      <% _ -> %>
        <div id={@id} class="aspect-square bg-neutral-900"></div>
    <% end %>
    """
  end
end
