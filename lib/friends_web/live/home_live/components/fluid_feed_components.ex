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
      <%!-- Minimal Header with User Menu --%>
      <.fluid_feed_header
        current_user={@current_user}
        user_private_rooms={@user_private_rooms}
        friends={@friends}
        online_friend_ids={@online_friend_ids}
        show_user_menu={@show_user_menu}
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
    <div class="sticky top-0 z-50 px-4 py-3 flex items-center justify-end bg-gradient-to-b from-black via-black/90 to-transparent">
      <%!-- User Menu Trigger (with 3s long-press easter egg) --%>
      <div class="relative">
        <button
          id="user-avatar-easter-egg"
          phx-click="toggle_user_menu"
          phx-hook="LongPressOrb"
          data-long-press-event="show_fullscreen_graph"
          data-long-press-duration="3000"
          class="w-9 h-9 rounded-full bg-neutral-800/80 border border-white/10 flex items-center justify-center overflow-hidden hover:border-white/30 hover:bg-neutral-700/80 transition-all cursor-pointer"
        >
          <span class="text-xs font-bold text-white/80"><%= String.first(@current_user.username) |> String.upcase() %></span>
        </button>

        <%!-- Floating User Menu (Now Global) --%>
      </div>
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
    <%!-- Backdrop --%>
    <div 
      class="fixed inset-0 z-[79]"
      phx-click="toggle_user_menu"
    ></div>

    <%!-- Floating Panel --%>
    <div class="fixed top-16 right-4 z-[200] w-72 max-h-[80vh] animate-in fade-in slide-in-from-top-2 duration-200">
      <div class="bg-neutral-900/95 backdrop-blur-xl border border-white/10 rounded-2xl shadow-2xl overflow-hidden flex flex-col">
        <%!-- User Header --%>
        <div class="px-4 py-3 border-b border-white/5 flex items-center gap-3">
          <div class="w-8 h-8 rounded-full bg-white/10 flex items-center justify-center">
            <span class="text-xs font-bold text-white"><%= String.first(@current_user.username) |> String.upcase() %></span>
          </div>
          <div class="flex-1 min-w-0">
            <div class="text-sm font-medium text-white truncate">@{@current_user.username}</div>
          </div>
        </div>

        <%!-- Content (scrolls only when naturally overflows) --%>
        <div class="overflow-y-auto" style="max-height: min(50vh, calc(100vh - 200px))">
          <%!-- Groups Section --%>
          <% groups_count = length(@user_private_rooms) %>
          <% groups_to_show = Enum.take(@user_private_rooms, 5) %>
          <div class="p-2">
            <button 
              phx-click={if groups_count > 0, do: "open_groups_sheet", else: "open_create_group_modal"}
              class="w-full px-2 py-1.5 text-[10px] font-medium text-white/40 uppercase tracking-wider flex items-center justify-between hover:text-white/60 transition-colors cursor-pointer group"
            >
              <span class="flex items-center gap-1.5">
                Spaces
                <%= if groups_count > 0 do %>
                  <span class="text-white/20 font-normal">{groups_count}</span>
                <% end %>
              </span>
              <%!-- + icon: always visible when <3 items, hover-only when more --%>
              <span 
                phx-click="open_create_group_modal"
                class={"w-5 h-5 rounded-full bg-white/5 flex items-center justify-center text-white/30 hover:bg-white/10 hover:text-white/60 transition-all #{if groups_count < 3, do: "", else: "opacity-0 group-hover:opacity-100"}"}
              >+</span>
            </button>
            <%!-- Groups list with fade effect on last item --%>
            <%= for {room, idx} <- Enum.with_index(groups_to_show) do %>
              <.link
                navigate={~p"/r/#{room.code}"}
                class={"flex items-center gap-2.5 px-2.5 py-2 rounded-xl hover:bg-white/5 transition-colors #{if idx == 4 and groups_count > 5, do: "opacity-40", else: ""}"}
              >
                <div class="w-7 h-7 rounded-lg bg-white/5 border border-white/10 flex items-center justify-center text-[10px] text-white/50">
                  #
                </div>
                <span class="text-sm text-white/80 truncate">{room.name || room.code}</span>
              </.link>
            <% end %>
            <%!-- Subtle overflow indicator (just dots, no text) --%>
            <%= if groups_count > 5 do %>
              <button
                phx-click="open_groups_sheet"
                class="w-full flex justify-center py-1 text-white/20 hover:text-white/40 transition-colors cursor-pointer"
              >
                ···
              </button>
            <% end %>
          </div>

          <%!-- People Section - PRESENCE-FIRST SORTED --%>
          <% 
            sorted_friends = Enum.sort_by(@friends, fn f -> 
              user = if Map.has_key?(f, :user), do: f.user, else: f
              is_online = @online_friend_ids && MapSet.member?(@online_friend_ids, user.id)
              {!is_online, user.username}
            end)
            friends_to_show = Enum.take(sorted_friends, 5)
            friends_count = length(@friends)
            online_count = if @online_friend_ids, do: Enum.count(@friends, fn f ->
              user = if Map.has_key?(f, :user), do: f.user, else: f
              MapSet.member?(@online_friend_ids, user.id)
            end), else: 0
          %>
          <% pending_count = length(@pending_requests) %>
          <div class={"p-2 border-t border-white/5 #{if pending_count > 0, do: "ring-1 ring-inset ring-blue-400/20", else: ""}"}>
            <button 
              phx-click="open_contact_search"
              phx-value-mode="list_contacts"
              class="w-full px-2 py-1.5 text-[10px] font-medium text-white/40 uppercase tracking-wider flex items-center justify-between hover:text-white/60 transition-colors cursor-pointer group"
            >
              <span class="flex items-center gap-1.5">
                People
                <%= if online_count > 0 do %>
                  <span class="w-1.5 h-1.5 rounded-full bg-green-400"></span>
                <% end %>
                <%= if pending_count > 0 do %>
                  <span class="w-4 h-4 rounded-full bg-blue-500/20 text-blue-400 text-[9px] flex items-center justify-center animate-pulse">{pending_count}</span>
                <% end %>
              </span>
              <%!-- Search icon: always visible when <3, hover-only when more --%>
              <span 
                phx-click="open_contact_search"
                phx-value-mode="add_contact"
                class={"w-5 h-5 rounded-full bg-white/5 flex items-center justify-center text-white/30 hover:bg-white/10 hover:text-white/60 transition-all #{if friends_count < 3, do: "", else: "opacity-0 group-hover:opacity-100"}"}
              >
                <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
                </svg>
              </span>
            </button>
            <%!-- Friends list (sorted: online first) with fade on last --%>
            <%= for {friend_wrapper, idx} <- Enum.with_index(friends_to_show) do %>
              <% friend = if Map.has_key?(friend_wrapper, :user), do: friend_wrapper.user, else: friend_wrapper %>
              <% dm_code = dm_room_code(@current_user.id, friend.id) %>
              <% is_online = @online_friend_ids && MapSet.member?(@online_friend_ids, friend.id) %>
              <.link
                navigate={~p"/r/#{dm_code}"}
                class={"flex items-center gap-2.5 px-2.5 py-2 rounded-xl hover:bg-white/5 transition-colors #{if is_online, do: "bg-white/[0.02]", else: ""} #{if idx == 4 and friends_count > 5, do: "opacity-40", else: ""}"}
              >
                <div
                  class={"w-7 h-7 rounded-full flex items-center justify-center text-[10px] font-bold transition-all #{if is_online, do: "ring-2 ring-green-400/40 scale-105", else: "opacity-60"}"}
                  style={"background-color: #{friend_color(friend)}; #{if is_online, do: "box-shadow: 0 0 12px 2px #{friend_color(friend)}40;", else: ""}"}
                >
                  <span style="color: white;">{String.first(friend.username) |> String.upcase()}</span>
                </div>
                <span class={"text-sm truncate #{if is_online, do: "text-white", else: "text-white/50"}"}>
                  @{friend.username}
                </span>
              </.link>
            <% end %>
            <%!-- Subtle overflow indicator --%>
            <%= if friends_count > 5 do %>
              <button
                phx-click="open_contact_search"
                phx-value-mode="list_contacts"
                class="w-full flex justify-center py-1 text-white/20 hover:text-white/40 transition-colors cursor-pointer"
              >
                ···
              </button>
            <% end %>
          </div>
        </div>

        <%!-- Actions Footer --%>
        <div class="p-2 border-t border-white/5 space-y-1">
          <button
            phx-click="open_settings_modal"
            class="w-full flex items-center gap-2.5 px-2.5 py-2 rounded-xl hover:bg-white/5 transition-colors text-left cursor-pointer"
          >
            <div class="w-7 h-7 rounded-lg bg-white/5 border border-white/10 flex items-center justify-center text-white/50">
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
              </svg>
            </div>
            <span class="text-sm text-white/70">Settings</span>
          </button>

          <button
            phx-click="sign_out"
            class="w-full flex items-center gap-2.5 px-2.5 py-2 rounded-xl hover:bg-red-500/10 transition-colors text-left cursor-pointer"
          >
            <div class="w-7 h-7 rounded-lg bg-red-500/10 flex items-center justify-center text-red-400/70">
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1" />
              </svg>
            </div>
            <span class="text-sm text-red-400/80">Sign Out</span>
          </button>
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
    <div class="relative flex items-center justify-center h-[70vh] overflow-hidden">
      <%!-- Ambient glow background --%>
      <div class="absolute inset-0 opacity-30">
        <div class="absolute top-1/4 left-1/4 w-64 h-64 rounded-full bg-gradient-to-br from-purple-500/20 to-transparent blur-3xl"></div>
        <div class="absolute bottom-1/3 right-1/4 w-48 h-48 rounded-full bg-gradient-to-br from-blue-500/20 to-transparent blur-3xl"></div>
      </div>

      <%!-- Static Graphic (Abstract Node Network) --%>
      <div class="relative w-64 h-64 opacity-30">
        <svg class="w-full h-full" viewBox="0 0 200 200" fill="none" xmlns="http://www.w3.org/2000/svg">
          <%!-- Central Node --%>
          <circle cx="100" cy="100" r="12" fill="white" fill-opacity="0.2" />
          
          <%!-- Satellite Nodes --%>
          <circle cx="100" cy="40" r="6" fill="white" fill-opacity="0.1" />
          <circle cx="160" cy="100" r="6" fill="white" fill-opacity="0.1" />
          <circle cx="100" cy="160" r="6" fill="white" fill-opacity="0.1" />
          <circle cx="40" cy="100" r="6" fill="white" fill-opacity="0.1" />
          
          <%!-- Connections --%>
          <line x1="100" y1="88" x2="100" y2="46" stroke="white" stroke-opacity="0.1" stroke-width="1" stroke-dasharray="4 4" />
          <line x1="112" y1="100" x2="154" y2="100" stroke="white" stroke-opacity="0.1" stroke-width="1" stroke-dasharray="4 4" />
          <line x1="100" y1="112" x2="100" y2="154" stroke="white" stroke-opacity="0.1" stroke-width="1" stroke-dasharray="4 4" />
          <line x1="88" y1="100" x2="46" y2="100" stroke="white" stroke-opacity="0.1" stroke-width="1" stroke-dasharray="4 4" />
          
          <%!-- Orbital Rings --%>
          <circle cx="100" cy="100" r="50" stroke="white" stroke-opacity="0.05" stroke-width="1" />
          <circle cx="100" cy="100" r="70" stroke="white" stroke-opacity="0.03" stroke-width="1" />
        </svg>
      </div>
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
          <div class="absolute top-2 right-2 px-2.5 py-1 rounded-full bg-black/50 backdrop-blur-md border border-white/10 flex items-center gap-1.5 shadow-sm">
            <svg class="w-3 h-3 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
            </svg>
            <span class="text-[10px] font-bold text-white">+{@item.photo_count}</span>
          </div>
          <%!-- Hover overlay --%>
          <div class="absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100 transition-opacity"></div>
        </div>

      <% :photo -> %>
        <%= if Map.get(@item, :content_type) in ["audio/encrypted", "audio/webm"] do %>
          <%!-- Voice Note --%>
          <div
            id={@id}
            class="aspect-square relative overflow-hidden bg-neutral-900 flex items-center justify-center"
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
                        <span class="w-2 h-2 rounded-full bg-green-400 presence-dot-online" style="color: #4ade80;"></span>
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
end

