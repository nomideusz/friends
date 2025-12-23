defmodule FriendsWeb.HomeLive.Components.FluidFeedComponents do
  @moduledoc """
  Fluid design components for the public feed.
  Content-first, unified input bar, no chat.
  """
  use FriendsWeb, :html
  import FriendsWeb.HomeLive.Helpers

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
  attr :friends, :list, default: []
  attr :show_user_menu, :boolean, default: false
  attr :welcome_graph_data, :map, default: nil
  attr :online_friend_ids, :any, default: nil

  def fluid_feed(assigns) do
    ~H"""
    <div
      id="fluid-feed"
      class="fixed inset-0 bg-black flex flex-col z-[100]"
      phx-hook="FriendsApp"
      phx-window-keydown="handle_keydown"
    >
      <%!-- Header --%>
      <.fluid_feed_header
        current_user={@current_user}
        user_private_rooms={@user_private_rooms}
        friends={@friends}
        online_friend_ids={@online_friend_ids}
        show_user_menu={@show_user_menu}
      />

      <%!-- Content Area (scrollable) - now starts from top --%>
      <%!-- Content Area (scrollable) - now starts from top --%>
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

      <%!-- Note: Content creation is now handled by toolbar's + button --%>
    </div>
    """
  end

  # ============================================================================
  # MINIMAL HEADER
  # Clean header with just user menu (groups, DMs, settings in floating panel)
  # ============================================================================

  attr :current_user, :map, required: true
  attr :user_private_rooms, :list, default: []
  attr :friends, :list, default: []
  attr :online_friend_ids, :any, default: nil
  attr :show_user_menu, :boolean, default: false

  def fluid_feed_header(assigns) do
    ~H"""
    <div class="sticky top-0 z-50 px-4 py-3 flex items-center justify-center bg-gradient-to-b from-black via-black/90 to-transparent">
      <%!-- Compact Search Pill - taps to open omnibox --%>
      <button
        type="button"
        phx-click="open_omnibox"
        class="flex items-center gap-2 bg-white/5 border border-white/10 rounded-full px-4 py-2 text-sm text-white/40 hover:bg-white/10 hover:border-white/20 hover:text-white/60 transition-all cursor-pointer"
      >
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
        </svg>
        <span class="hidden sm:inline">Search...</span>
      </button>
    </div>
    """
  end

  # ============================================================================
  # USER MENU PANEL (Floating Fluid Design)
  # Groups, DMs, Settings - replaces the old nav drawer
  # ============================================================================

  attr :current_user, :map, required: true
  attr :user_private_rooms, :list, default: []
  attr :friends, :list, default: []
  attr :online_friend_ids, :any, default: nil
  attr :pending_requests, :list, default: []

  def user_menu_panel(assigns) do
    ~H"""
    <%!-- Bottom Sheet Style User Menu --%>
    <div id="user-menu-sheet" class="fixed inset-0 z-[200]">
      <%!-- Backdrop --%>
      <div
        class="absolute inset-0 bg-black/60 backdrop-blur-sm animate-in fade-in duration-200"
        phx-click="toggle_user_menu"
      ></div>

      <%!-- Sheet --%>
      <div class="absolute inset-x-0 bottom-0 z-10 flex justify-center animate-in slide-in-from-bottom duration-300 pointer-events-none">
        <div class="w-full max-w-lg bg-neutral-900/95 backdrop-blur-xl border-t border-x border-white/10 rounded-t-3xl shadow-2xl pointer-events-auto">
          <%!-- Handle --%>
          <div class="py-3 flex justify-center cursor-pointer" phx-click="toggle_user_menu">
            <div class="w-10 h-1 rounded-full bg-white/20"></div>
          </div>

          <%!-- User Header --%>
          <div class="px-6 pb-4 flex items-center gap-4">
            <div class="w-12 h-12 rounded-full bg-white/10 flex items-center justify-center text-lg font-bold text-white border border-white/10">
              <%= String.first(@current_user.username) |> String.upcase() %>
            </div>
            <div class="flex-1 min-w-0">
              <div class="text-base font-semibold text-white truncate">@{@current_user.username}</div>
              <div class="text-xs text-white/40">Online</div>
            </div>
          </div>

          <%!-- Actions --%>
          <div class="px-4 pb-8 space-y-1">
            <button
              phx-click="open_settings_modal"
              class="w-full py-3 px-4 rounded-xl bg-white/5 hover:bg-white/10 text-left text-sm text-white/80 hover:text-white flex items-center gap-3 transition-colors cursor-pointer"
            >
              <svg class="w-5 h-5 text-white/50" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
              </svg>
              Settings
            </button>

            <button
              phx-click="sign_out"
              class="w-full py-3 px-4 rounded-xl hover:bg-red-500/10 text-left text-sm text-white/50 hover:text-red-400 flex items-center gap-3 transition-colors cursor-pointer"
            >
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1" />
              </svg>
              Sign Out
            </button>
          </div>
        </div>
      </div>
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
    ~H"""
    <div class="relative flex items-center justify-center h-full overflow-hidden">
      <%= if @welcome_graph_data do %>
        <%!-- Live Network Graph as empty state --%>
        <div
          id="feed-empty-welcome-graph"
          phx-hook="WelcomeGraph"
          phx-update="ignore"
          class="absolute inset-0"
          data-graph-data={Jason.encode!(@welcome_graph_data)}
          data-current-user-id={if @current_user, do: @current_user.id, else: nil}
          data-always-show="true"
          data-hide-controls="true"
        >
        </div>
      <% else %>
        <%!-- Fallback: Static ambient graphic --%>
        <div class="absolute inset-0 opacity-30">
          <div class="absolute top-1/4 left-1/4 w-64 h-64 rounded-full bg-gradient-to-br from-purple-500/20 to-transparent blur-3xl"></div>
          <div class="absolute bottom-1/3 right-1/4 w-48 h-48 rounded-full bg-gradient-to-br from-blue-500/20 to-transparent blur-3xl"></div>
        </div>
      <% end %>
    </div>
    """
  end

  # ============================================================================
  # FEED GRID
  # Full-width grid for photos and notes
  # ============================================================================

  attr :feed_items, :list, required: true
  attr :current_user, :map, required: true
  attr :is_admin, :boolean, default: false

  def fluid_feed_grid(assigns) do
    # Check if current user is admin
    is_admin = Friends.Social.is_admin?(assigns.current_user)
    assigns = assign(assigns, :is_admin, is_admin)

    ~H"""
    <div
      id="fluid-feed-grid"
      phx-update="stream"
      class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-1 p-1"
    >
      <%= for {dom_id, item} <- @feed_items do %>
        <.fluid_feed_item id={dom_id} item={item} current_user={@current_user} is_admin={@is_admin} />
      <% end %>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :item, :map, required: true
  attr :current_user, :map, required: true
  attr :is_admin, :boolean, default: false

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
          <div class="absolute top-2 right-2 px-2.5 py-1 rounded-full bg-black/50 backdrop-blur-md border border-white/10 flex items-center gap-1.5 shadow-sm">
            <svg class="w-3 h-3 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
            </svg>
            <span class="text-[10px] font-bold text-white">+{@item.photo_count}</span>
          </div>
          <%!-- Hover overlay --%>
          <div class="absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100 transition-opacity"></div>
          <%!-- Delete gallery button (admin only) --%>
          <%= if @is_admin do %>
            <button
              type="button"
              phx-click="delete_gallery"
              phx-value-batch_id={@item.batch_id}
              data-confirm="Delete entire gallery (#{@item.photo_count} photos)?"
              class="absolute top-2 left-2 w-6 h-6 rounded-full bg-black/60 text-white/70 hover:text-red-400 opacity-0 group-hover:opacity-100 transition-all cursor-pointer flex items-center justify-center z-10"
            >
              <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          <% end %>
        </div>

      <% :photo -> %>
        <%= if Map.get(@item, :content_type) in ["audio/encrypted", "audio/webm"] do %>
          <%!-- Voice Note --%>
          <div
            id={@id}
            class="aspect-square relative overflow-hidden bg-neutral-900 flex items-center justify-center group"
            phx-hook="FeedVoicePlayer"
            data-item-id={@item.id}
            data-content-type={@item.content_type}
          >
            <div class="hidden" id={"feed-voice-data-#{@item.id}"} data-src={@item.image_data} data-encrypted={@item.image_data} data-nonce={@item.thumbnail_data}></div>
            <button class="feed-voice-play-btn w-12 h-12 rounded-full bg-white/10 border border-white/20 flex items-center justify-center text-white hover:bg-white/20 transition-all cursor-pointer">
              <svg class="w-5 h-5 ml-0.5" fill="currentColor" viewBox="0 0 24 24">
                <path d="M8 5v14l11-7z" />
              </svg>
            </button>
            <%!-- Delete button for owner or admin --%>
            <%= if @item.user_id == "user-#{@current_user.id}" or @is_admin do %>
              <button
                type="button"
                phx-click="delete_photo"
                phx-value-id={@item.id}
                data-confirm="Delete this voice message?"
                class="absolute top-2 right-2 w-6 h-6 rounded-full bg-black/60 text-white/70 hover:text-red-400 opacity-0 group-hover:opacity-100 transition-all cursor-pointer flex items-center justify-center z-10"
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

            <%!-- Delete button (owner or admin) --%>
            <% is_owner = @item.user_id == "user-#{@current_user.id}" or @item.user_id == @current_user.id %>
            <%= if is_owner or @is_admin do %>
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

          <%!-- Delete button (owner or admin) --%>
          <% is_owner = @item.user_id == "user-#{@current_user.id}" or @item.user_id == @current_user.id %>
          <%= if is_owner or @is_admin do %>
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
            phx-hook="FeedVoiceRecorder"
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
  attr :online_friend_ids, :any, default: nil

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
                  <% is_online = @online_friend_ids && MapSet.member?(@online_friend_ids, partner.id) %>
                  <.link
                    navigate={~p"/r/#{dm.code}"}
                    class="flex items-center gap-3 p-2.5 rounded-xl hover:bg-white/5 transition-colors"
                  >
                    <div
                      class={"w-8 h-8 rounded-full flex items-center justify-center text-xs font-bold text-white #{if is_online, do: "avatar-online", else: ""}"}
                      style={"background-color: #{partner.color}; color: #{partner.color};"}
                    >
                      <span style="color: white;">{String.first(partner.name)}</span>
                    </div>
                    <span class="text-sm text-white/80 truncate flex items-center gap-2">
                      {partner.name}
                      <%= if is_online do %>
                        <span class="text-[10px] text-green-400/70">Here now</span>
                      <% end %>
                    </span>
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
        %{name: username, color: user_color(id), id: id}
      _ ->
        %{name: "?", color: "#888", id: nil}
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

  # ============================================================================
  # FEED ADD SHEET
  # Bottom sheet for adding content from feed toolbar's + button
  # ============================================================================

  attr :show, :boolean, default: false
  attr :uploads, :map, default: nil

  def feed_add_sheet(assigns) do
    ~H"""
    <%= if @show do %>
      <div class="fixed inset-0 z-[200]" phx-window-keydown="toggle_add_menu" phx-key="escape">
        <%!-- Backdrop --%>
        <div
          class="absolute inset-0 bg-black/70 backdrop-blur-sm animate-in fade-in duration-200"
          phx-click="toggle_add_menu"
        ></div>

        <%!-- Sheet --%>
        <div class="absolute inset-x-0 bottom-0 z-10 flex justify-center animate-in slide-in-from-bottom duration-300">
          <div class="w-full max-w-lg bg-neutral-900/95 backdrop-blur-xl border-t border-x border-white/10 rounded-t-3xl shadow-2xl">
            <%!-- Handle --%>
            <div class="py-3 flex justify-center cursor-pointer" phx-click="toggle_add_menu">
              <div class="w-10 h-1 rounded-full bg-white/20"></div>
            </div>

            <%!-- Options --%>
            <div class="px-4 pb-8 grid grid-cols-4 gap-4">
              <%!-- Photo --%>
              <form id="feed-add-sheet-upload" phx-change="validate_feed_photo" phx-submit="save_feed_photo" class="contents">
                <label class="flex flex-col items-center gap-2 p-4 rounded-2xl bg-white/5 border border-white/10 hover:bg-white/10 hover:border-white/20 transition-all cursor-pointer">
                  <div class="w-12 h-12 rounded-full bg-gradient-to-br from-pink-500 to-rose-600 flex items-center justify-center">
                    <svg class="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
                    </svg>
                  </div>
                  <span class="text-xs text-white/70">Photo</span>
                  <%= if @uploads && @uploads[:feed_photo] do %>
                    <.live_file_input upload={@uploads.feed_photo} class="sr-only" />
                  <% end %>
                </label>
              </form>

              <%!-- Note --%>
              <button
                type="button"
                phx-click="open_feed_note_modal"
                class="flex flex-col items-center gap-2 p-4 rounded-2xl bg-white/5 border border-white/10 hover:bg-white/10 hover:border-white/20 transition-all cursor-pointer"
              >
                <div class="w-12 h-12 rounded-full bg-gradient-to-br from-amber-500 to-orange-600 flex items-center justify-center">
                  <svg class="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                  </svg>
                </div>
                <span class="text-xs text-white/70">Note</span>
              </button>

              <%!-- Voice --%>
              <button
                id="feed-add-sheet-voice"
                phx-hook="FeedVoiceRecorder"
                phx-click="start_voice_recording"
                class="flex flex-col items-center gap-2 p-4 rounded-2xl bg-white/5 border border-white/10 hover:bg-white/10 hover:border-white/20 transition-all cursor-pointer"
              >
                <div class="w-12 h-12 rounded-full bg-gradient-to-br from-purple-500 to-violet-600 flex items-center justify-center">
                  <svg class="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z" />
                  </svg>
                </div>
                <span class="text-xs text-white/70">Voice</span>
              </button>

              <%!-- New Group --%>
              <button
                type="button"
                phx-click="open_create_group_modal"
                class="flex flex-col items-center gap-2 p-4 rounded-2xl bg-white/5 border border-white/10 hover:bg-white/10 hover:border-white/20 transition-all cursor-pointer"
              >
                <div class="w-12 h-12 rounded-full bg-gradient-to-br from-blue-500 to-cyan-600 flex items-center justify-center">
                  <svg class="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z" />
                  </svg>
                </div>
                <span class="text-xs text-white/70">Group</span>
              </button>
            </div>
          </div>
        </div>
      </div>
    <% end %>
    """
  end
end

