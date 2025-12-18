defmodule FriendsWeb.HomeLive.Components.FluidFeedComponents do
  @moduledoc """
  Fluid design components for the public feed.
  Content-first, unified input bar, no chat.
  """
  use FriendsWeb, :html

  # ============================================================================
  # FLUID FEED LAYOUT
  # The main wrapper for public feed with content-first approach
  # ============================================================================

  attr :current_user, :map, required: true
  attr :feed_items, :list, required: true
  attr :feed_item_count, :integer, default: 0
  attr :uploads, :map, default: nil
  attr :uploading, :boolean, default: false
  attr :recording_voice, :boolean, default: false
  attr :no_more_items, :boolean, default: false
  attr :user_private_rooms, :list, default: []
  attr :direct_rooms, :list, default: []
  attr :show_nav_panel, :boolean, default: false
  attr :welcome_graph_data, :map, default: nil

  def fluid_feed(assigns) do
    ~H"""
    <div
      id="fluid-feed"
      class="fixed inset-0 bg-black flex flex-col z-[100]"
      phx-hook="FriendsApp"
      phx-window-keydown="handle_keydown"
    >
      <%!-- Minimal Header --%>
      <.fluid_feed_header
        current_user={@current_user}
        show_nav_panel={@show_nav_panel}
      />

      <%!-- Content Area (scrollable) --%>
      <div class="flex-1 overflow-y-auto overflow-x-hidden pb-24">
        <%= if @feed_item_count == 0 do %>
          <.fluid_feed_empty_state 
            welcome_graph_data={@welcome_graph_data} 
            current_user={@current_user}
          />
        <% else %>
          <.fluid_feed_grid feed_items={@feed_items} current_user={@current_user} />
        <% end %>

        <%!-- Load More --%>
        <%= unless @no_more_items do %>
          <div class="flex justify-center py-8">
            <button
              type="button"
              phx-click="load_more"
              phx-disable-with="..."
              class="w-10 h-10 rounded-full border border-white/20 text-white/40 hover:border-white/40 hover:text-white/70 transition-colors cursor-pointer flex items-center justify-center"
            >
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
              </svg>
            </button>
          </div>
        <% end %>
      </div>

      <%!-- Unified Input Bar (photo, note, voice - no chat) --%>
      <.feed_input_bar
        uploads={@uploads}
        uploading={@uploading}
        recording_voice={@recording_voice}
      />

      <%!-- Navigation Panel (floating) --%>
      <%= if @show_nav_panel do %>
        <.nav_panel
          current_user={@current_user}
          user_private_rooms={@user_private_rooms}
          direct_rooms={@direct_rooms}
        />
      <% end %>
    </div>
    """
  end

  # ============================================================================
  # MINIMAL HEADER
  # Network title, nav toggle, user button
  # ============================================================================

  attr :current_user, :map, required: true
  attr :show_nav_panel, :boolean, default: false

  def fluid_feed_header(assigns) do
    ~H"""
    <div class="sticky top-0 z-50 px-4 py-3 flex items-center justify-between bg-gradient-to-b from-black via-black/90 to-transparent">
      <%!-- Left: Nav Toggle + Title --%>
      <div class="flex items-center gap-3">
        <button
          phx-click="toggle_nav_panel"
          class="w-8 h-8 rounded-full flex items-center justify-center text-white/50 hover:text-white hover:bg-white/10 transition-colors cursor-pointer"
        >
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16M4 18h16" />
          </svg>
        </button>

        <span class="text-sm font-bold text-white">Network</span>
      </div>

      <%!-- Right: User Avatar --%>
      <button
        phx-click="open_settings_modal"
        class="w-8 h-8 rounded-full bg-neutral-800 border border-white/10 flex items-center justify-center overflow-hidden hover:border-white/30 transition-colors cursor-pointer"
      >
        <span class="text-[10px] font-bold text-white/70"><%= String.first(@current_user.username) |> String.upcase() %></span>
      </button>
    </div>
    """
  end

  # ============================================================================
  # EMPTY STATE
  # Ethereal floating orbs representing the network
  # ============================================================================

  attr :welcome_graph_data, :map, default: nil
  attr :current_user, :map, default: nil

  def fluid_feed_empty_state(assigns) do
    # Take first 7 nodes for the orbs
    nodes = if assigns.welcome_graph_data, do: Enum.take(assigns.welcome_graph_data.nodes || [], 7), else: []
    assigns = assign(assigns, :nodes, nodes)

    ~H"""
    <div class="relative flex items-center justify-center h-[70vh] overflow-hidden">
      <%!-- Ambient glow background --%>
      <div class="absolute inset-0 opacity-30">
        <div class="absolute top-1/4 left-1/4 w-64 h-64 rounded-full bg-gradient-to-br from-purple-500/20 to-transparent blur-3xl"></div>
        <div class="absolute bottom-1/3 right-1/4 w-48 h-48 rounded-full bg-gradient-to-br from-blue-500/20 to-transparent blur-3xl"></div>
        <div class="absolute top-1/2 left-1/2 w-32 h-32 -translate-x-1/2 -translate-y-1/2 rounded-full bg-gradient-to-br from-white/10 to-transparent blur-2xl"></div>
      </div>

      <%!-- Floating Orbs --%>
      <div class="relative w-80 h-80">
        <%!-- Connection lines (ethereal) --%>
        <svg class="absolute inset-0 w-full h-full" viewBox="0 0 320 320">
          <defs>
            <linearGradient id="line-gradient" x1="0%" y1="0%" x2="100%" y2="0%">
              <stop offset="0%" stop-color="white" stop-opacity="0.1" />
              <stop offset="50%" stop-color="white" stop-opacity="0.3" />
              <stop offset="100%" stop-color="white" stop-opacity="0.1" />
            </linearGradient>
          </defs>
          <%!-- Draw some ethereal connection lines --%>
          <line x1="160" y1="80" x2="100" y2="140" stroke="url(#line-gradient)" stroke-width="1" class="animate-pulse" />
          <line x1="160" y1="80" x2="220" y2="140" stroke="url(#line-gradient)" stroke-width="1" class="animate-pulse" style="animation-delay: 0.5s" />
          <line x1="160" y1="80" x2="160" y2="160" stroke="url(#line-gradient)" stroke-width="1" class="animate-pulse" style="animation-delay: 1s" />
          <line x1="100" y1="140" x2="80" y2="220" stroke="url(#line-gradient)" stroke-width="1" class="animate-pulse" style="animation-delay: 0.3s" />
          <line x1="220" y1="140" x2="240" y2="220" stroke="url(#line-gradient)" stroke-width="1" class="animate-pulse" style="animation-delay: 0.7s" />
          <line x1="160" y1="160" x2="160" y2="250" stroke="url(#line-gradient)" stroke-width="1" class="animate-pulse" style="animation-delay: 1.2s" />
        </svg>

        <%!-- Central orb (current user) --%>
        <div 
          class="absolute top-[15%] left-1/2 -translate-x-1/2 w-14 h-14 rounded-full flex items-center justify-center"
          style="background: radial-gradient(circle at 30% 30%, rgba(255,255,255,0.3), rgba(255,255,255,0.05)); box-shadow: 0 0 40px rgba(255,255,255,0.2), 0 0 80px rgba(255,255,255,0.1);"
        >
          <span class="text-sm font-bold text-white/80">
            <%= if @current_user, do: String.first(@current_user.username) |> String.upcase(), else: "?" %>
          </span>
        </div>

        <%!-- Orbiting nodes --%>
        <%= for {node, idx} <- Enum.with_index(@nodes) do %>
          <% 
            # Position orbs in an organic, asymmetric pattern
            positions = [
              {"18%", "40%", "0.3s"},
              {"60%", "38%", "0.6s"},
              {"38%", "55%", "0.9s"},
              {"15%", "72%", "0.4s"},
              {"50%", "78%", "0.7s"},
              {"72%", "68%", "1.0s"},
              {"85%", "45%", "0.5s"}
            ]
            {left, top, delay} = Enum.at(positions, idx, {"50%", "50%", "0s"})
            size = if idx < 2, do: "w-10 h-10", else: "w-8 h-8"
          %>
          <div 
            class={"absolute #{size} rounded-full flex items-center justify-center transition-all duration-1000 hover:scale-125"}
            style={"left: #{left}; top: #{top}; background: radial-gradient(circle at 30% 30%, #{node.color}90, #{node.color}20); box-shadow: 0 0 20px #{node.color}40, 0 0 40px #{node.color}20; animation: float 6s ease-in-out infinite; animation-delay: #{delay};"}
          >
            <span class="text-[10px] font-bold text-white/90">
              <%= String.first(node.username) |> String.upcase() %>
            </span>
          </div>
        <% end %>
      </div>

      <%!-- Subtle hint text --%>
      <div class="absolute bottom-8 left-1/2 -translate-x-1/2 text-center">
        <p class="text-[10px] text-white/20 tracking-widest uppercase">Your network awaits</p>
      </div>

      <%!-- Floating animation keyframes --%>
      <style>
        @keyframes float {
          0%, 100% { transform: translateY(0px); }
          50% { transform: translateY(-8px); }
        }
      </style>
    </div>
    """
  end

  # ============================================================================
  # FEED GRID
  # Full-width grid for photos and notes
  # ============================================================================

  attr :feed_items, :list, required: true
  attr :current_user, :map, required: true

  def fluid_feed_grid(assigns) do
    ~H"""
    <div
      id="fluid-feed-grid"
      phx-update="stream"
      class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-1 p-1"
    >
      <%= for {dom_id, item} <- @feed_items do %>
        <.fluid_feed_item id={dom_id} item={item} current_user={@current_user} />
      <% end %>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :item, :map, required: true
  attr :current_user, :map, required: true

  def fluid_feed_item(assigns) do
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
          <div class="absolute top-2 right-2 px-2 py-0.5 rounded-full bg-black/60 backdrop-blur-sm">
            <span class="text-[10px] font-bold text-white">{@item.photo_count}</span>
          </div>
          <%!-- Hover overlay --%>
          <div class="absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100 transition-opacity"></div>
        </div>

      <% :photo -> %>
        <%= if Map.get(@item, :content_type) == "audio/encrypted" do %>
          <%!-- Voice Note --%>
          <div
            id={@id}
            class="aspect-square relative overflow-hidden bg-neutral-900 flex items-center justify-center"
            phx-hook="FeedVoicePlayer"
            data-item-id={@item.id}
          >
            <div class="hidden" id={"feed-voice-data-#{@item.id}"} data-encrypted={@item.image_data} data-nonce={@item.thumbnail_data}></div>
            <button class="feed-voice-play-btn w-12 h-12 rounded-full bg-white/10 border border-white/20 flex items-center justify-center text-white hover:bg-white/20 transition-all cursor-pointer">
              <svg class="w-5 h-5 ml-0.5" fill="currentColor" viewBox="0 0 24 24">
                <path d="M8 5v14l11-7z" />
              </svg>
            </button>
          </div>
        <% else %>
          <%!-- Photo --%>
          <div
            id={@id}
            class="aspect-square relative overflow-hidden cursor-pointer group"
            phx-click="view_feed_photo"
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

            <%!-- Delete button (own photos only) --%>
            <%= if @item.user_id == @current_user.id do %>
              <button
                type="button"
                phx-click="delete_photo"
                phx-value-id={@item.id}
                data-confirm="Delete?"
                class="absolute top-2 right-2 w-6 h-6 rounded-full bg-black/60 text-white/70 hover:text-red-400 opacity-0 group-hover:opacity-100 transition-all cursor-pointer flex items-center justify-center"
              >
                <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            <% end %>
          </div>
        <% end %>

      <% :note -> %>
        <%!-- Note --%>
        <div
          id={@id}
          class="aspect-square relative overflow-hidden bg-neutral-900/50 border border-white/5 cursor-pointer group p-4 flex flex-col"
          phx-click="view_feed_note"
          phx-value-note_id={@item.id}
        >
          <p class="text-sm text-white/80 line-clamp-5 flex-1">{@item.content}</p>
          <div class="mt-2 flex items-center gap-2">
            <div class="w-4 h-4 rounded-full" style={"background-color: #{@item.user_color || "#888"}"}></div>
            <span class="text-[10px] text-white/40">@{@item.user_name}</span>
          </div>

          <%!-- Delete button (own notes only) --%>
          <%= if @item.user_id == @current_user.id do %>
            <button
              type="button"
              phx-click="delete_note"
              phx-value-id={@item.id}
              data-confirm="Delete?"
              phx-click-stop
              class="absolute top-2 right-2 w-6 h-6 rounded-full bg-black/60 text-white/70 hover:text-red-400 opacity-0 group-hover:opacity-100 transition-all cursor-pointer flex items-center justify-center"
            >
              <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          <% end %>
        </div>

      <% _ -> %>
        <div id={@id} class="aspect-square bg-neutral-900"></div>
    <% end %>
    """
  end

  # ============================================================================
  # FEED INPUT BAR
  # Photo, Note, Voice - no chat
  # ============================================================================

  attr :uploads, :map, default: nil
  attr :uploading, :boolean, default: false
  attr :recording_voice, :boolean, default: false

  def feed_input_bar(assigns) do
    ~H"""
    <div class="fixed bottom-0 left-0 right-0 z-50 p-4 bg-gradient-to-t from-black via-black/95 to-transparent">
      <div class="max-w-lg mx-auto">
        <div class="flex items-center justify-center gap-4">
          <%!-- Photo button --%>
          <form id="fluid-feed-upload-form" phx-change="validate_feed_photo" phx-submit="save_feed_photo" class="contents">
            <label class="w-12 h-12 rounded-full bg-white/5 border border-white/10 flex items-center justify-center text-white/50 hover:text-white hover:bg-white/10 hover:border-white/20 transition-all cursor-pointer">
              <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
              </svg>
              <%= if @uploads && @uploads[:feed_photo] do %>
                <.live_file_input upload={@uploads.feed_photo} class="sr-only" />
              <% end %>
            </label>
          </form>

          <%!-- Note button --%>
          <button
            phx-click="open_feed_note_modal"
            class="w-12 h-12 rounded-full bg-white/5 border border-white/10 flex items-center justify-center text-white/50 hover:text-white hover:bg-white/10 hover:border-white/20 transition-all cursor-pointer"
          >
            <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
            </svg>
          </button>

          <%!-- Voice button --%>
          <button
            id="fluid-feed-voice-btn"
            phx-click="start_voice_recording"
            class={"w-12 h-12 rounded-full flex items-center justify-center transition-all cursor-pointer #{if @recording_voice, do: "bg-red-500 text-white animate-pulse border-transparent", else: "bg-white/5 border border-white/10 text-white/50 hover:text-white hover:bg-white/10 hover:border-white/20"}"}
          >
            <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z" />
            </svg>
          </button>
        </div>

        <%!-- Upload progress --%>
        <%= if @uploading do %>
          <div class="mt-3 h-1 bg-white/10 rounded-full overflow-hidden">
            <div class="h-full bg-blue-500 animate-pulse" style="width: 50%"></div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # ============================================================================
  # NAV PANEL
  # Floating panel with groups and direct messages
  # ============================================================================

  attr :current_user, :map, required: true
  attr :user_private_rooms, :list, default: []
  attr :direct_rooms, :list, default: []

  def nav_panel(assigns) do
    ~H"""
    <div class="fixed inset-0 z-[80]">
      <%!-- Backdrop --%>
      <div
        class="absolute inset-0 bg-black/60 backdrop-blur-sm animate-in fade-in duration-200"
        phx-click="toggle_nav_panel"
      ></div>

      <%!-- Panel --%>
      <div class="absolute top-0 left-0 bottom-0 w-[80%] max-w-xs animate-in slide-in-from-left duration-200">
        <div class="h-full bg-neutral-900/95 backdrop-blur-xl border-r border-white/10 flex flex-col">
          <%!-- Header --%>
          <div class="px-4 py-4 border-b border-white/5 flex items-center justify-between">
            <span class="text-sm font-bold text-white">Navigate</span>
            <button
              phx-click="toggle_nav_panel"
              class="w-6 h-6 rounded-full flex items-center justify-center text-white/50 hover:text-white hover:bg-white/10 transition-colors cursor-pointer"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>

          <%!-- Groups --%>
          <div class="flex-1 overflow-y-auto p-3 space-y-4">
            <%= if @user_private_rooms != [] do %>
              <div class="space-y-1">
                <%= for room <- @user_private_rooms do %>
                  <.link
                    navigate={~p"/r/#{room.code}"}
                    class="flex items-center gap-3 p-2.5 rounded-xl hover:bg-white/5 transition-colors"
                  >
                    <div class="w-8 h-8 rounded-full bg-white/5 border border-white/10 flex items-center justify-center text-xs font-bold text-white/50">
                      #
                    </div>
                    <span class="text-sm text-white/80 truncate">{room.name || room.code}</span>
                  </.link>
                <% end %>
              </div>
            <% end %>

            <%!-- Direct --%>
            <%= if @direct_rooms != [] do %>
              <div class="pt-3 border-t border-white/5 space-y-1">
                <%= for dm <- @direct_rooms do %>
                  <% partner = get_dm_partner(dm, @current_user.id) %>
                  <.link
                    navigate={~p"/r/#{dm.code}"}
                    class="flex items-center gap-3 p-2.5 rounded-xl hover:bg-white/5 transition-colors"
                  >
                    <div
                      class="w-8 h-8 rounded-full flex items-center justify-center text-xs font-bold text-white"
                      style={"background-color: #{partner.color}"}
                    >
                      {String.first(partner.name)}
                    </div>
                    <span class="text-sm text-white/80 truncate">{partner.name}</span>
                  </.link>
                <% end %>
              </div>
            <% end %>
          </div>

          <%!-- Create Group Button --%>
          <div class="p-3 border-t border-white/5">
            <button
              phx-click="open_create_group_modal"
              class="w-full py-2.5 rounded-xl bg-white/5 border border-white/10 text-sm font-medium text-white/70 hover:bg-white/10 hover:text-white transition-colors cursor-pointer flex items-center justify-center"
            >
              +
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Get the partner info from a DM room's members
  defp get_dm_partner(room, current_user_id) do
    partner = 
      room.members
      |> Enum.find(fn m -> m.user_id != current_user_id end)

    case partner do
      %{user: %{username: username, id: id}} ->
        %{name: username, color: user_color(id)}
      _ ->
        %{name: "?", color: "#888"}
    end
  end

  defp user_color(id) when is_integer(id) do
    colors = [
      "#FF6B6B", "#4ECDC4", "#45B7D1", "#96CEB4",
      "#FFEAA7", "#DDA0DD", "#98D8C8", "#F7DC6F",
      "#BB8FCE", "#85C1E9", "#F8B500", "#00CED1"
    ]
    Enum.at(colors, rem(id, length(colors)))
  end
  defp user_color(_), do: "#888"
end
