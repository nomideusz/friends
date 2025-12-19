defmodule FriendsWeb.HomeLive.Components.RoomComponents do
  @moduledoc """
  Function components for the room view and sidebar.
  """
  use FriendsWeb, :html
  import FriendsWeb.HomeLive.Helpers
  alias FriendsWeb.HomeLive.Components.CardComponents

  # --- Sidebar (Dashboard) ---

  attr :users, :list, required: true
  attr :rooms, :list, required: true
  attr :new_room_name, :string, default: nil
  attr :contacts_collapsed, :boolean, default: false
  attr :groups_collapsed, :boolean, default: false

  def sidebar(assigns) do
    ~H"""
    <div class="w-full lg:w-80 flex-shrink-0 space-y-4">
      <%!-- Contacts --%>
      <div class="aether-card">
        <button
          phx-click="toggle_contacts"
          class="w-full flex items-center justify-between p-6 cursor-pointer hover:bg-white/5 transition-colors"
        >
          <h3 class="text-xs font-bold text-white/40 uppercase tracking-wider">
            Contacts ({length(@users)})
          </h3>
          <span class="text-white/40 text-sm">
            <%= if @contacts_collapsed, do: "▼", else: "▲" %>
          </span>
        </button>

        <%= if !@contacts_collapsed do %>
          <div class="px-6 pb-6">
            <div class="space-y-3 mb-4">
              <%= for friend <- Enum.take(@users, 5) do %>
                <div
                  class="flex items-center justify-between group cursor-pointer"
                  phx-click="open_dm"
                  phx-value-user_id={friend.user.id}
                >
                  <div class="flex items-center gap-3">
                    <div class="relative">
                      <div
                        class="w-10 h-10 rounded-full flex items-center justify-center text-sm font-bold text-white shadow-sm border border-white/10"
                        style={"background-color: #{friend_color(friend.user)}"}
                      >
                        {String.first(friend.user.username)}
                      </div>
                    </div>

                    <div>
                      <p class="text-sm font-bold text-white/50 group-hover:text-white transition-colors">
                        {friend.user.username}
                      </p>
                    </div>
                  </div>

                  <div class="w-2 h-2 rounded-full bg-neutral-300 group-hover:bg-opal-rose transition-colors">
                  </div>
                </div>
              <% end %>

              <%= if @users == [] do %>
                <div class="text-center py-4">
                  <p class="text-xs text-white/30 italic mb-2">No contacts yet</p>
                  <.link
                    navigate="/network"
                    class="px-3 py-1.5 rounded-lg bg-white/5 hover:bg-neutral-700 text-xs text-white/70 font-medium transition-colors inline-block border border-white/5"
                  >
                    + Add Friends
                  </.link>
                </div>
              <% end %>
            </div>

            <%= if length(@users) > 0 do %>
              <.link
                navigate="/network"
                class="text-xs font-bold text-blue-400 hover:text-blue-300 transition-colors underline"
              >
                View all contacts →
              </.link>
            <% end %>
          </div>
        <% end %>
      </div>
       <%!-- Groups --%>
      <div class="aether-card">
        <button
          phx-click="toggle_groups"
          class="w-full flex items-center justify-between p-6 cursor-pointer hover:bg-white/5 transition-colors"
        >
          <h3 class="text-xs font-bold text-white/40 uppercase tracking-wider">
            Groups ({length(Enum.reject(@rooms, &(&1.room_type == "dm")))})
          </h3>
          <span class="text-white/40 text-sm">
            <%= if @groups_collapsed, do: "▼", else: "▲" %>
          </span>
        </button>

        <%= if !@groups_collapsed do %>
          <div class="px-6 pb-6">
            <div class="space-y-3 mb-6">
              <%= for room <- Enum.reject(@rooms, &(&1.room_type == "dm")) do %>
                <.link
                  navigate={~p"/r/#{room.code}"}
                  class="w-full flex items-center gap-3 p-2 rounded hover:bg-white/5 transition-colors group text-left"
                >
                  <div class="w-10 h-10 rounded-full border border-white/10 flex items-center justify-center text-lg font-bold text-white/50 group-hover:text-white group-hover:border-white/30 group-hover:scale-105 transition-all">
                    #
                  </div>

                  <div class="flex-1 min-w-0">
                    <p class="text-sm font-bold text-white/50 group-hover:text-white truncate">
                      {room.name || room.code}
                    </p>

                    <p class="text-xs text-white/30 truncate">{length(room.members)} members</p>
                  </div>
                </.link>
              <% end %>
            </div>

            <form phx-submit="create_group" phx-change="update_room_form" novalidate>
              <div class="pt-4 border-t border-white/10">
                <input
                  type="text"
                  name="name"
                  value={@new_room_name}
                  placeholder="New Group Name"
                  required
                  class="w-full bg-black/30 border border-white/10 rounded-lg px-3 py-2 text-sm text-white placeholder-white/30 focus:outline-none focus:border-blue-500 mb-3"
                />
                <button
                  type="submit"
                  class="w-full py-2 btn-aether text-white/50 hover:text-white hover:border-white/30 text-xs font-bold uppercase tracking-wider cursor-pointer"
                >
                  Create Group
                </button>
              </div>
            </form>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # --- Network Info ---

  attr :feed_mode, :string, required: true
  attr :current_user, :map, required: true
  attr :trusted_friends, :list, default: []
  attr :outgoing_trust_requests, :list, default: []

  def network_info_card(assigns) do
    ~H"""
    <%= if @feed_mode == "friends" && @current_user do %>
      <div class="mb-10 p-6 aether-card shadow-sm">
        <div class="flex items-center justify-between mb-3">
          <div class="text-xs font-bold uppercase tracking-wider text-white/40">your trust network</div>
          
          <button
            type="button"
            phx-click="open_network_modal"
            class="text-xs font-bold uppercase tracking-wider text-opal-azure hover:text-opal-cyan cursor-pointer hover:underline"
          >
            manage →
          </button>
        </div>
        
        <%= if @trusted_friends != [] do %>
          <div class="flex flex-wrap gap-2">
            <%= for friend <- Enum.take(@trusted_friends, 10) do %>
              <div class="flex items-center gap-2 px-2 py-1 bg-white/5 rounded-full">
                <div
                  class="w-2 h-2 rounded-full"
                  style={"background-color: #{trusted_user_color(friend.trusted_user)}"}
                /> <span class="text-xs text-white/70">@{friend.trusted_user.username}</span>
              </div>
            <% end %>
            
            <%= if length(@trusted_friends) > 10 do %>
              <div class="px-2 py-1 text-xs text-white/40">
                +{length(@trusted_friends) - 10} more
              </div>
            <% end %>
          </div>
          
          <div class="mt-3 text-xs text-white/30">
            showing activity from {length(@trusted_friends)} trusted connection{if length(
                                                                                     @trusted_friends
                                                                                   ) != 1, do: "s"}
          </div>
        <% else %>
          <%= if @outgoing_trust_requests != [] do %>
            <div class="space-y-2">
              <div class="text-sm text-white/50">waiting for confirmation...</div>
              
              <div class="flex flex-wrap gap-2">
                <%= for req <- Enum.take(@outgoing_trust_requests, 10) do %>
                  <div class="flex items-center gap-2 px-2 py-1 bg-white/5 rounded-full">
                    <div
                      class="w-2 h-2 rounded-full"
                      style={"background-color: #{trusted_user_color(req.trusted_user)}"}
                    /> <span class="text-xs text-white/70">@{req.trusted_user.username}</span>
                  </div>
                <% end %>
              </div>
              
              <div class="text-xs text-white/30">they'll appear here after they confirm</div>
            </div>
          <% else %>
            <div class="flex items-center gap-3 p-4 bg-black/30 border border-white/10 rounded-lg">
              <div class="text-white/30">
                <svg class="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="1.5"
                    d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z"
                  >
                  </path>
                </svg>
              </div>
              
              <div class="flex-1">
                <p class="text-sm text-white/40 font-medium">no trusted connections yet</p>
                
                <p class="text-xs text-white/30 mt-0.5">
                  add friends in settings to see their activity
                </p>
              </div>
            </div>
          <% end %>
        <% end %>
      </div>
    <% end %>
    """
  end

  # --- View States ---

  attr :uploads, :map, required: true

  def upload_progress(assigns) do
    ~H"""
    <%= if @uploads && @uploads[:photo] && @uploads.photo.entries != [] do %>
      <% 
        entries = @uploads.photo.entries
        count = length(entries)
        avg_progress = div(Enum.reduce(entries, 0, & &1.progress + &2), count)
      %>
      <div class="mb-4 aether-card p-3 animate-in fade-in slide-in-from-top-2 duration-300">
        <div class="flex items-center gap-4">
          <div class="w-10 h-10 rounded-full bg-blue-500/10 flex items-center justify-center shrink-0 border border-blue-500/20">
            <svg class="w-5 h-5 text-blue-400 animate-pulse" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-8l-4-4m0 0L8 8m4-4v12" />
            </svg>
          </div>
          
          <div class="flex-1 min-w-0">
             <div class="flex justify-between items-end mb-1.5">
               <span class="text-xs font-bold text-white/70 uppercase tracking-wider">
                 Uploading <%= count %> <%= if count == 1, do: "photo", else: "photos" %>...
               </span>
               <span class="text-xs font-mono font-bold text-blue-400"><%= avg_progress %>%</span>
             </div>
             
             <div class="h-1.5 bg-white/5 rounded-full overflow-hidden">
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
               class="text-white/40 hover:text-white p-2 hover:bg-white/5 rounded-lg transition-colors cursor-pointer"
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

  attr :room_access_denied, :boolean, required: true
  attr :room, :map, required: true
  attr :current_user, :map, required: true

  def access_denied(assigns) do
    ~H"""
    <%= if @room_access_denied do %>
      <div class="text-center py-20">
        <p class="text-4xl mb-4">🔒</p>
        
        <p class="text-white/50 text-sm font-medium">private room</p>
        
        <p class="text-white/30 text-xs mt-2">you don't have access to this room</p>
        
        <%= if is_nil(@current_user) do %>
          <a
            href={"/auth?join=#{@room.code}"}
            class="inline-block mt-4 px-4 py-2 bg-emerald-500 text-black text-sm font-medium rounded-lg hover:bg-emerald-400 transition-colors"
          >
            sign in to join
          </a>
        <% else %>
          <p class="text-neutral-700 text-xs mt-4">ask the owner to invite you</p>
        <% end %>
      </div>
    <% end %>
    """
  end


  attr :item_count, :integer, required: true
  attr :current_user, :map, required: true
  attr :room_access_denied, :boolean, default: false
  attr :feed_mode, :string, default: "private"
  attr :network_filter, :string, default: "all"

  def empty_room(assigns) do
    ~H"""
    <%= if @item_count == 0 and (is_nil(@current_user) or @room_access_denied) do %>
      <div class="text-center py-20">
        <%= if @feed_mode == "friends" do %>
          <%= if @network_filter == "me" do %>
            <div class="mb-4 opacity-40">
              <svg
                class="w-16 h-16 mx-auto text-white/40"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="1.5"
                  d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z"
                >
                </path>
              </svg>
            </div>
            
            <p class="text-white/40 text-base font-medium mb-2">you haven't posted yet</p>
            
            <p class="text-white/30 text-sm">share a photo or note to see it here</p>
          <% else %>
            <div class="mb-4 opacity-40">
              <svg
                class="w-16 h-16 mx-auto text-white/40"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="1.5"
                  d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z"
                >
                </path>
              </svg>
            </div>
            
            <p class="text-neutral-900 text-base font-bold mb-2">no activity from your network</p>
            
            <p class="text-neutral-800 text-sm font-medium">
              add trusted connections to see their photos and notes
            </p>
          <% end %>
        <% else %>
          <div class="mb-4 opacity-40">
            <svg
              class="w-16 h-16 mx-auto text-white/40"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="1.5"
                d="M20 13V6a2 2 0 00-2-2H6a2 2 0 00-2 2v7m16 0v5a2 2 0 01-2 2H6a2 2 0 01-2-2v-5m16 0h-2.586a1 1 0 00-.707.293l-2.414 2.414a1 1 0 01-.707.293h-3.172a1 1 0 01-.707-.293l-2.414-2.414A1 1 0 006.586 13H4"
              >
              </path>
            </svg>
          </div>
          
          <p class="text-neutral-900 text-base font-bold mb-2">this space is empty</p>
          
          <p class="text-neutral-800 text-sm font-medium">share a photo or note to get started</p>
        <% end %>
      </div>
    <% end %>
    """
  end

  # --- Action Bars ---

  attr :current_user, :map, required: true
  attr :room_access_denied, :boolean, required: true
  attr :uploads, :map, required: true
  attr :uploading, :boolean, default: false
  attr :recording_voice, :boolean, default: false
  attr :room, :map, required: true

  def mobile_action_bar(assigns) do
    # Mobile uses FAB (Floating Action Button) for uploads, so this is now empty
    ~H"""
    """
  end

  def room_actions_bar(assigns) do
    ~H"""
    <%= if not is_nil(@current_user) and not @room_access_denied and @uploads do %>
      <div class="hidden sm:block">
        <CardComponents.actions_bar
          uploads={@uploads}
          uploading={@uploading}
          recording_voice={@recording_voice}
          note_event="open_note_modal"
          voice_button_id="grid-voice-record"
          voice_hook="GridVoiceRecorder"
          room_id={@room.id}
          upload_key={:photo}
          id_prefix="desktop"
        />
      </div>
    <% end %>
    """
  end

  # --- Room Grid & Items ---

  attr :items, :list, required: true
  attr :room, :map, required: true
  attr :current_user, :map, required: true

  def room_grid(assigns) do
    ~H"""
    <div
      id="items-grid"
      phx-update="stream"

      class="contents"
    >
      <%= for {dom_id, item} <- @items do %>
        <.room_item id={dom_id} item={item} room={@room} current_user={@current_user} />
      <% end %>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :item, :map, required: true
  attr :room, :map, required: true
  attr :current_user, :map, required: true

  def room_item(assigns) do
    ~H"""
    <%= if Map.get(@item, :type) == :gallery do %>
      <div
        id={@id}
        class="photo-item group relative aspect-square overflow-hidden aether-card cursor-pointer animate-in fade-in zoom-in-95 duration-300"
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

        <%!-- Overlay --%>
        <div class="absolute inset-0 bg-gradient-to-t from-black/60 via-transparent to-transparent opacity-0 group-hover:opacity-100 transition-opacity">
           <div class="absolute bottom-2 left-2 right-2">
             <div class="text-xs font-bold text-white/40 truncate">@<%= @item.user_name || "unknown" %></div>
           </div>
        </div>
      </div>
    <% else %>
      <%= if Map.get(@item, :type) == :photo do %>
      <div
        id={@id}
        class="photo-item group relative aspect-square overflow-hidden aether-card cursor-pointer transition-all hover:border-white/20 hover:-translate-y-1 animate-in fade-in zoom-in-95 duration-300"
        phx-click={if Map.get(@item, :content_type) != "audio/encrypted", do: "view_full_image"}
        phx-value-photo_id={@item.id}
      >
        <%= if Map.get(@item, :content_type) == "audio/encrypted" do %>
          <div
            class="w-full h-full flex flex-col items-center justify-center p-3 sm:p-4 text-center relative z-10"
            id={"grid-voice-player-#{@item.id}"}
            data-item-id={@item.id}
            data-room-id={@room.id}
            phx-hook="GridVoicePlayer"
          >
            <div
              class="hidden"
              id={"grid-voice-data-#{@item.id}"}
              data-encrypted={@item.image_data}
              data-nonce={@item.thumbnail_data}
            >
            </div>
            
            <!-- Waveform Canvas -->
            <canvas
              class="visualizer-canvas absolute inset-0 w-full h-full opacity-40 pointer-events-none"
              width="300"
              height="300"
            ></canvas>
            
            <div class="relative z-10 flex flex-col items-center w-full">
              <div class="w-10 h-10 sm:w-12 sm:h-12 rounded-full bg-white/10 flex items-center justify-center mb-2 sm:mb-3 ring-1 ring-white/20">
                <svg class="w-5 h-5 sm:w-6 sm:h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z" />
                </svg>
              </div>
              
              <span class="text-[10px] font-medium text-white/50 uppercase tracking-widest mb-2">Voice Note</span>
              
              <button class="grid-voice-play-btn w-10 h-10 rounded-full bg-white/10 hover:bg-white/20 border border-white/20 hover:border-white/40 flex items-center justify-center text-white transition-all group-hover:scale-110 active:scale-95 cursor-pointer z-20 mb-2">
                <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
                  <path d="M8 5v14l11-7z" />
                </svg>
              </button>
              
              <div class="w-full max-w-[120px] h-1.5 bg-white/5/50 rounded-full overflow-hidden border border-white/5">
                <div class="grid-voice-progress h-full bg-blue-500 w-0 transition-all"></div>
              </div>
              
              <div class="mt-2 flex items-center gap-1 px-2 py-0.5 rounded-full bg-white/5 border border-white/10 shadow-sm">
                <div class="w-2 h-2 rounded-full bg-blue-500 animate-pulse"></div>
                <span class="text-[10px] text-white/50 font-medium">@{@item.user_name || "unknown"}</span>
              </div>
            </div>
          </div>
        <% else %>
          <%= if @item.thumbnail_data do %>
            <img
              src={@item.thumbnail_data}
              alt=""
              class="w-full h-full object-cover"
              decoding="async"
            />
          <% else %>
            <div class="w-full h-full flex items-center justify-center bg-white/5 skeleton border-2 border-dashed border-neutral-600">
              <div class="text-center">
                <svg
                  class="w-8 h-8 mx-auto mb-2 text-white/40"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="1.5"
                    d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"
                  >
                  </path>
                </svg> <span class="text-white/50 text-xs">loading</span>
              </div>
            </div>
          <% end %>
        <% end %>
         <%!-- Overlay on hover (only for photos, not voice) --%>
        <%= if Map.get(@item, :content_type) != "audio/encrypted" do %>
          <div class="absolute inset-0 bg-gradient-to-t from-black/60 via-transparent to-transparent opacity-0 group-hover:opacity-100 transition-opacity">
            <div class="absolute bottom-2 left-2 right-2">
              <div class="text-xs font-bold text-white/40 truncate">@{@item.user_name || "unknown"}</div>
            </div>
            
            <%= if @item.user_id == @current_user.id do %>
              <button
                type="button"
                phx-click="delete_photo"
                phx-value-id={@item.id}
                data-confirm="delete?"
                class="absolute top-2 right-2 text-white/40 hover:text-red-500 text-xs cursor-pointer"
              >
                delete
              </button>
            <% end %>
          </div>
        <% end %>
      </div>
    <% else %>
      <%!-- Note card (matching feed style) --%>
      <div
        id={@id}
        class="note-item aether-card group relative aspect-square overflow-hidden cursor-pointer transition-all hover:-translate-y-1 animate-in fade-in zoom-in-95 duration-300"
        phx-click="view_full_note"
        phx-value-id={@item.id}
        phx-value-content={@item.content}
        phx-value-user={@item.user_name}
        phx-value-time={format_time(@item.inserted_at)}
      >
        <div class="w-full h-full p-4 flex flex-col">
          <div class="flex-1 overflow-hidden">
            <p class="text-sm text-white line-clamp-6">{@item.content}</p>
          </div>
          
          <div class="mt-2 pt-2 border-t border-white/10">
            <div class="flex items-center gap-2">
              <div
                class="w-5 h-5 rounded-full"
                style={"background-color: #{@item.user_color || "#888"}"}
              >
              </div>
               <span class="text-xs text-white/40 truncate">@{@item.user_name || "unknown"}</span>
            </div>
          </div>
        </div>

        <%= if @item.user_id == @current_user.id do %>
          <button
            type="button"
            phx-click="delete_note"
            phx-value-id={@item.id}
            data-confirm="delete?"
            class="absolute top-2 right-2 text-white/40 hover:text-red-500 transition-colors opacity-0 group-hover:opacity-100 p-2 z-10"
            phx-click-stop
          >
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
            </svg>
          </button>
        <% end %>
      </div>
    <% end %>
    <% end %>
    """
  end

  attr :no_more_items, :boolean, required: true

  def load_more_button(assigns) do
    ~H"""
    <%= unless @no_more_items do %>
      <div class="flex justify-center mt-6">
        <button
          type="button"
          phx-click="load_more"
          phx-disable-with="loading..."
          class="px-4 py-2 text-sm border border-neutral-700 text-white/70 hover:border-neutral-500 hover:text-white transition-colors cursor-pointer min-w-[140px]"
        >
          show more
        </button>
      </div>
    <% end %>
    """
  end
end
