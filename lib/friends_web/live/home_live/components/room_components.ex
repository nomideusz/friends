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
          <h3 class="text-xs font-bold text-neutral-500 uppercase tracking-wider">
            Contacts ({length(@users)})
          </h3>
          <span class="text-neutral-500 text-sm">
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
                        class="w-10 h-10 rounded-full flex items-center justify-center text-sm font-bold text-white shadow-sm border border-neutral-200"
                        style={"background-color: #{friend_color(friend.user)}"}
                      >
                        {String.first(friend.user.username)}
                      </div>
                    </div>

                    <div>
                      <p class="text-sm font-bold text-neutral-400 group-hover:text-neutral-200 transition-colors">
                        {friend.user.username}
                      </p>
                    </div>
                  </div>

                  <div class="w-2 h-2 rounded-full bg-neutral-300 group-hover:bg-opal-rose transition-colors">
                  </div>
                </div>
              <% end %>

              <%= if @users == [] do %>
                <p class="text-xs text-neutral-600 italic">No contacts yet</p>
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
          <h3 class="text-xs font-bold text-neutral-500 uppercase tracking-wider">
            Groups ({length(Enum.reject(@rooms, &(&1.room_type == "dm")))})
          </h3>
          <span class="text-neutral-500 text-sm">
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
                  <div class="w-10 h-10 rounded-full border border-white/10 flex items-center justify-center text-lg font-bold text-neutral-400 group-hover:text-white group-hover:border-white/30 group-hover:scale-105 transition-all">
                    #
                  </div>

                  <div class="flex-1 min-w-0">
                    <p class="text-sm font-bold text-neutral-400 group-hover:text-neutral-200 truncate">
                      {room.name || room.code}
                    </p>

                    <p class="text-xs text-neutral-600 truncate">{length(room.members)} members</p>
                  </div>
                </.link>
              <% end %>
            </div>

            <form phx-submit="create_group" phx-change="update_room_form" novalidate>
              <div class="pt-4 border-t border-neutral-200">
                <input
                  type="text"
                  name="name"
                  value={@new_room_name}
                  placeholder="New Group Name"
                  required
                  class="w-full bg-black/30 border border-white/10 rounded-lg px-3 py-2 text-sm text-white placeholder-neutral-600 focus:outline-none focus:border-blue-500 mb-3"
                />
                <button
                  type="submit"
                  class="w-full py-2 btn-aether text-neutral-400 hover:text-white hover:border-white/30 text-xs font-bold uppercase tracking-wider cursor-pointer"
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
          <div class="text-xs font-bold uppercase tracking-wider text-neutral-500">your trust network</div>
          
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
              <div class="flex items-center gap-2 px-2 py-1 bg-neutral-800 rounded-full">
                <div
                  class="w-2 h-2 rounded-full"
                  style={"background-color: #{trusted_user_color(friend.trusted_user)}"}
                /> <span class="text-xs text-neutral-300">@{friend.trusted_user.username}</span>
              </div>
            <% end %>
            
            <%= if length(@trusted_friends) > 10 do %>
              <div class="px-2 py-1 text-xs text-neutral-500">
                +{length(@trusted_friends) - 10} more
              </div>
            <% end %>
          </div>
          
          <div class="mt-3 text-xs text-neutral-600">
            showing activity from {length(@trusted_friends)} trusted connection{if length(
                                                                                     @trusted_friends
                                                                                   ) != 1, do: "s"}
          </div>
        <% else %>
          <%= if @outgoing_trust_requests != [] do %>
            <div class="space-y-2">
              <div class="text-sm text-neutral-400">waiting for confirmation...</div>
              
              <div class="flex flex-wrap gap-2">
                <%= for req <- Enum.take(@outgoing_trust_requests, 10) do %>
                  <div class="flex items-center gap-2 px-2 py-1 bg-neutral-800 rounded-full">
                    <div
                      class="w-2 h-2 rounded-full"
                      style={"background-color: #{trusted_user_color(req.trusted_user)}"}
                    /> <span class="text-xs text-neutral-300">@{req.trusted_user.username}</span>
                  </div>
                <% end %>
              </div>
              
              <div class="text-xs text-neutral-600">they'll appear here after they confirm</div>
            </div>
          <% else %>
            <div class="flex items-center gap-3 p-4 bg-black/30 border border-white/10 rounded-lg">
              <div class="text-neutral-600">
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
                <p class="text-sm text-neutral-500 font-medium">no trusted connections yet</p>
                
                <p class="text-xs text-neutral-600 mt-0.5">
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
    <%= if @uploads do %>
      <%= for entry <- @uploads.photo.entries do %>
        <div class="mb-4 bg-neutral-900 p-3">
          <div class="flex items-center gap-3">
            <div class="flex-1 bg-neutral-800 h-1">
              <div class="bg-white h-full transition-all" style={"width: #{entry.progress}%"} />
            </div>
             <span class="text-xs text-neutral-500">{entry.progress}%</span>
            <button
              type="button"
              phx-click="cancel_upload"
              phx-value-ref={entry.ref}
              class="text-neutral-500 hover:text-white text-xs cursor-pointer"
            >
              cancel
            </button>
          </div>
        </div>
      <% end %>
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
        
        <p class="text-neutral-400 text-sm font-medium">private room</p>
        
        <p class="text-neutral-600 text-xs mt-2">you don't have access to this room</p>
        
        <%= if is_nil(@current_user) do %>
          <a
            href={"/register?join=#{@room.code}"}
            class="inline-block mt-4 px-4 py-2 bg-emerald-500 text-black text-sm font-medium rounded-lg hover:bg-emerald-400 transition-colors"
          >
            register to join
          </a>
          <p class="text-neutral-600 text-xs mt-2">
            or <a href="/login" class="text-emerald-400 hover:text-emerald-300">login</a>
            if you have an account
          </p>
        <% else %>
          <p class="text-neutral-700 text-xs mt-4">ask the owner to invite you</p>
        <% end %>
      </div>
    <% end %>
    """
  end

  attr :item_count, :integer, required: true
  attr :current_user, :map, required: true
  attr :room_access_denied, :boolean, required: true
  attr :feed_mode, :string
  attr :network_filter, :string

  def empty_room(assigns) do
    ~H"""
    <%= if @item_count == 0 and (is_nil(@current_user) or @room_access_denied) do %>
      <%!-- This condition seems wrong in original code: if item_count == 0 AND (is_nil(user) OR access_denied). 
           Wait, logic in home_live.ex was:
           <%= if @item_count == 0 and (is_nil(@current_user) or @room_access_denied) do %>
           Actually looking at the file (lines 737):
           <%= if @item_count == 0 and (is_nil(@current_user) or @room_access_denied) do %>
           Wait, if user IS logged in and access is NOT denied, and count is 0?
           It falls through to empty space?
           Actually line 737 logic seems to cover only when user is NOT logged in or access denied?
           But if they are logged in and access granted, they see Empty Room message?
           Ah, I misread the original file. 
           Line 737: if @item_count == 0 and (is_nil(@current_user) or @room_access_denied) ...
           Wait, if access is denied, we show access denied block (line 721).
           If access is GRANTED (else block 735), then we check if item_count == 0.
           But the condition inside `else` (line 737) assumes is_nil(current_user) or access_denied? 
           That implies we DON'T show empty state if user is logged in and has access?
           That seems buggy or I'm misreading.
           Let's look at line 737 again in `home_live.ex`.
           `<%= if @item_count == 0 and (is_nil(@current_user) or @room_access_denied) do %>`
           If I am logged in (`!is_nil(@current_user)`) and have access (`!@room_access_denied`), then this condition is FALSE.
           So nothing renders?
           Then where is the "Your feed is empty" message for legitimate users?
           Ah, maybe the logic is flawed in the original file or I am missing something.
           Wait, looking at line 766 in Step 152 output.
           There is NO `else` for line 737.
           So if I am logged in and have access, and item count is 0, I see... NOTHING?
           Just the action bars (uploaded form etc, 815 -> 862).
           But no "Empty" message?
           Wait, look at lines 739-765. These are the empty messages.
           BUT they are wrapped in `if @item_count == 0 and ...`.
           If I am logged in, `not is_nil` is true. `is_nil` is false.
           So `and` clause fails.
           So legitimate users don't see empty state?
           This might be a bug I should fix or I am misunderstanding.
           Actually, let's copy the logic exactly as is for now to avoid changing behavior implicitly.
           Wait, I see `<%!-- Content grid --%>` at 736.
      Then `if @item_count == 0 ...`.
      Then `else` at 811.
      So if logic is FALSE (e.g. valid user), it goes to 812 (Grid).
      So if `item_count == 0` and valid user, it goes to Grid.
      But Grid iterates `@streams.items`. If empty, it renders nothing.
      So valid users see nothing but the upload buttons?
      Maybe that's intended.
      However, looking at lines 739+ it has checks for `@feed_mode == "friends"`.
      This implies it expects to show something.
      Maybe `or` precedence? `if count == 0 and (nil user OR denied)`.
      If I am a valid user, I want to see "you haven't posted yet".
      There seems to be a mismatch.
      Let's look at `feed_mode` check. It is used in Dashboard usually?
      This is "Room View" (line 622).
      Does Room View use `feed_mode`?
      Maybe `feed_mode` is for the "Network" tab?
      In `mount_room`, `feed_mode` defaults to "public"?

      I will extract `empty_room` with the SAME logic for now.

      Wait, I'll extract the condition outside:
      In `home_live.ex`:
      `<%= if @item_count == 0 and (is_nil(@current_user) or @room_access_denied) do %>
        ` <.empty_room ... /> `
      <% else %>
        `
        ... grid ...
        `
      <% end %>`

      Actually, the `else` block at 811 corresponds to the `if` at 737.
      So I should extract the content of the `if` into `empty_room_message` or similar.
      --%>
      <div class="text-center py-20">
        <%= if @feed_mode == "friends" do %>
          <%= if @network_filter == "me" do %>
            <div class="mb-4 opacity-40">
              <svg
                class="w-16 h-16 mx-auto text-neutral-500"
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
            
            <p class="text-neutral-500 text-base font-medium mb-2">you haven't posted yet</p>
            
            <p class="text-neutral-600 text-sm">share a photo or note to see it here</p>
          <% else %>
            <div class="mb-4 opacity-40">
              <svg
                class="w-16 h-16 mx-auto text-neutral-500"
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
              class="w-16 h-16 mx-auto text-neutral-500"
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
    ~H"""
    <%= if not is_nil(@current_user) and not @room_access_denied and @uploads do %>
      <div class="sm:hidden">
        <CardComponents.actions_bar
          uploads={@uploads}
          uploading={@uploading}
          recording_voice={@recording_voice}
          note_event="open_note_modal"
          voice_button_id="grid-voice-record-mobile"
          voice_hook="GridVoiceRecorder"
          room_id={@room.id}
          upload_key={:photo}
          id_prefix="mobile"
          skip_file_input={true}
        />
      </div>
    <% end %>
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
      phx-hook="PhotoGrid"
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
            
            <!-- Decorative wave background -->
            <div class="absolute inset-0 opacity-10" style="background-image: url('data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMjAiIGhlaWdodD0iMjAiIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyI+PHBhdGggZD0iTTEgMTBoMThNMTAgMXYxOCIgc3Ryb2tlPSJjdXJyZW50Q29xb3Igc3Ryb2tlLXdpZHRoPSIyIiBmaWxsPSJub25lIiAvPjwvc3ZnPg==');"></div>
            
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
                <span class="text-[10px] text-neutral-400 font-medium">@{@item.user_name || "unknown"}</span>
              </div>
            </div>
          </div>
        <% else %>
          <%= if @item.thumbnail_data do %>
            <img
              src={@item.thumbnail_data}
              alt=""
              class="w-full h-full object-cover loaded"
              decoding="async"
            />
          <% else %>
            <div class="w-full h-full flex items-center justify-center bg-neutral-800 skeleton border-2 border-dashed border-neutral-600">
              <div class="text-center">
                <svg
                  class="w-8 h-8 mx-auto mb-2 text-neutral-500"
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
                </svg> <span class="text-neutral-400 text-xs">loading</span>
              </div>
            </div>
          <% end %>
        <% end %>
         <%!-- Overlay on hover (only for photos, not voice) --%>
        <%= if Map.get(@item, :content_type) != "audio/encrypted" do %>
          <div class="absolute inset-0 bg-gradient-to-t from-black/60 via-transparent to-transparent opacity-0 group-hover:opacity-100 transition-opacity">
            <div class="absolute bottom-2 left-2 right-2">
              <div class="text-xs font-bold text-neutral-500 truncate">@{@item.user_name || "unknown"}</div>
            </div>
            
            <%= if @item.user_id == @current_user.id do %>
              <button
                type="button"
                phx-click="delete_photo"
                phx-value-id={@item.id}
                data-confirm="delete?"
                class="absolute top-2 right-2 text-neutral-500 hover:text-red-500 text-xs cursor-pointer"
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
            <p class="text-sm text-neutral-200 line-clamp-6">{@item.content}</p>
          </div>
          
          <div class="mt-2 pt-2 border-t border-neutral-200">
            <div class="flex items-center gap-2">
              <div
                class="w-5 h-5 rounded-full"
                style={"background-color: #{@item.user_color || "#888"}"}
              >
              </div>
               <span class="text-xs text-neutral-500 truncate">@{@item.user_name || "unknown"}</span>
            </div>
          </div>
        </div>

        <%= if @item.user_id == @current_user.id do %>
          <button
            type="button"
            phx-click="delete_note"
            phx-value-id={@item.id}
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
          class="px-4 py-2 text-sm border border-neutral-700 text-neutral-300 hover:border-neutral-500 hover:text-white transition-colors cursor-pointer min-w-[140px]"
        >
          show more
        </button>
      </div>
    <% end %>
    """
  end
end
