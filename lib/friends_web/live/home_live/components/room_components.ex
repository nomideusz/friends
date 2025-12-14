defmodule FriendsWeb.HomeLive.Components.RoomComponents do
  @moduledoc """
  Function components for the room view and sidebar.
  """
  use FriendsWeb, :html
  import FriendsWeb.HomeLive.Helpers

  # --- Sidebar (Dashboard) ---

  attr :users, :list, required: true
  attr :rooms, :list, required: true
  attr :new_room_name, :string, default: nil

  def sidebar(assigns) do
    ~H"""
    <div class="w-full lg:w-80 flex-shrink-0 space-y-8">
      <%!-- Contacts --%>
      <div class="glass rounded-2xl p-6 border border-white/5">
        <h3 class="text-xs font-bold text-neutral-500 uppercase tracking-wider mb-4">Contacts</h3>
        
        <div class="space-y-3">
          <%= for friend <- @users do %>
            <div
              class="flex items-center justify-between group cursor-pointer"
              phx-click="open_dm"
              phx-value-user_id={friend.user.id}
            >
              <div class="flex items-center gap-3">
                <div class="relative">
                  <div
                    class="w-10 h-10 rounded-full flex items-center justify-center text-sm font-bold text-white shadow-lg"
                    style={"background-color: #{friend_color(friend.user)}"}
                  >
                    {String.first(friend.user.username)}
                  </div>
                </div>
                
                <div>
                  <p class="text-sm font-medium text-neutral-200 group-hover:text-white transition-colors">
                    {friend.user.username}
                  </p>
                </div>
              </div>
              
              <div class="w-2 h-2 rounded-full bg-neutral-800 group-hover:bg-neutral-700 transition-colors">
              </div>
            </div>
          <% end %>
          
          <%= if @users == [] do %>
            <p class="text-xs text-neutral-600 italic">No contacts yet</p>
          <% end %>
        </div>
      </div>
       <%!-- Groups --%>
      <form
        phx-submit="create_group"
        phx-change="update_room_form"
        class="glass rounded-2xl p-6 border border-white/5"
        novalidate
      >
        <h3 class="text-xs font-bold text-neutral-500 uppercase tracking-wider mb-4">Groups</h3>
        
        <div class="space-y-3 mb-6">
          <%= for room <- Enum.reject(@rooms, &(&1.room_type == "dm")) do %>
            <.link
              navigate={~p"/r/#{room.code}"}
              class="w-full flex items-center gap-3 p-2 rounded-xl hover:bg-white/5 transition-colors group text-left"
            >
              <div class="w-10 h-10 rounded-full bg-neutral-800 flex items-center justify-center text-lg group-hover:scale-105 transition-transform">
                #
              </div>
              
              <div class="flex-1 min-w-0">
                <p class="text-sm font-medium text-neutral-300 group-hover:text-white truncate">
                  {room.name || room.code}
                </p>
                
                <p class="text-xs text-neutral-600 truncate">{length(room.members)} members</p>
              </div>
            </.link>
          <% end %>
        </div>
        
        <div class="pt-4 border-t border-white/5">
          <input
            type="text"
            name="name"
            value={@new_room_name}
            placeholder="New Group Name"
            required
            class="w-full bg-neutral-900/50 border border-neutral-800 rounded-lg px-3 py-2 text-sm text-neutral-300 placeholder-neutral-600 focus:outline-none focus:border-neutral-600 mb-3"
          />
          <button
            type="submit"
            class="w-full py-2 bg-white/5 hover:bg-white/10 text-neutral-300 hover:text-white text-xs font-medium rounded-lg transition-colors"
          >
            Create Group
          </button>
        </div>
      </form>
       <%!-- Info footer --%>
      <div class="px-6 pb-6">
        <div class="p-4 bg-neutral-950/50 border border-neutral-800/50 rounded-xl">
          <div class="flex items-start gap-3">
            <span class="text-lg">🔒</span>
            <div class="text-xs text-neutral-500">
              <p class="font-medium text-neutral-400 mb-1">Private by default</p>
              
              <p>
                Only people you invite can access your group. Share the link or add members directly.
              </p>
            </div>
          </div>
        </div>
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
      <div class="mb-10 p-6 opal-card opal-aurora rounded-2xl">
        <div class="flex items-center justify-between mb-3">
          <div class="text-xs text-neutral-500">your trust network</div>
          
          <button
            type="button"
            phx-click="open_network_modal"
            class="text-xs text-green-500 hover:text-green-400 cursor-pointer"
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
            <div class="flex items-center gap-3 p-4 bg-neutral-900/50 border border-neutral-800 rounded-lg">
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
            
            <p class="text-neutral-500 text-base font-medium mb-2">no activity from your network</p>
            
            <p class="text-neutral-600 text-sm">
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
          
          <p class="text-neutral-500 text-base font-medium mb-2">this space is empty</p>
          
          <p class="text-neutral-600 text-sm">share a photo or note to get started</p>
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
      <div class="sm:hidden flex items-stretch gap-2 mb-4">
        <%!-- Mobile Photo Button (triggers the desktop file input) --%>
        <label
          for={@uploads.photo.ref}
          class="flex-1 flex flex-col items-center justify-center gap-1.5 py-3 rounded-xl bg-neutral-800/80 hover:bg-white/10 transition-all cursor-pointer active:scale-95"
        >
          <svg class="w-6 h-6 text-neutral-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
          </svg>
          <span class="text-[10px] font-medium text-neutral-500">
            {if @uploading, do: "...", else: "Photo"}
          </span>
        </label> <%!-- Mobile Note Button --%>
        <button
          type="button"
          phx-click="open_note_modal"
          class="flex-1 flex flex-col items-center justify-center gap-1.5 py-3 rounded-xl bg-neutral-800/80 hover:bg-white/10 transition-all cursor-pointer active:scale-95"
        >
          <svg class="w-6 h-6 text-neutral-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
          </svg> <span class="text-[10px] font-medium text-neutral-500">Note</span>
        </button> <%!-- Mobile Voice Button --%>
        <button
          type="button"
          id="grid-voice-record-mobile"
          phx-hook="GridVoiceRecorder"
          data-room-id={@room.id}
          class={"flex-1 flex flex-col items-center justify-center gap-1.5 py-3 rounded-xl transition-all cursor-pointer active:scale-95 #{if @recording_voice, do: "bg-red-500/30 animate-pulse", else: "bg-neutral-800/80 hover:bg-white/10"}"}
        >
          <%= if @recording_voice do %>
            <div class="w-4 h-4 bg-red-500 rounded-sm"></div>
          <% else %>
            <svg
              class="w-6 h-6 text-neutral-400"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M12 4v16m8-8H4"
              />
            </svg>
          <% end %>
          
          <span class={"text-[10px] font-medium #{if @recording_voice, do: "text-red-400", else: "text-neutral-500"}"}>
            {if @recording_voice, do: "Stop", else: "Voice"}
          </span>
        </button>
      </div>
    <% end %>
    """
  end

  def room_actions_bar(assigns) do
    ~H"""
    <%= if not is_nil(@current_user) and not @room_access_denied and @uploads do %>
      <div class="hidden sm:flex items-stretch gap-3 mb-6">
        <%!-- Photo Upload --%>
        <form id="upload-form" phx-change="validate" phx-submit="save" class="contents">
          <label
            for={@uploads.photo.ref}
            class="flex-1 flex items-center justify-center gap-2 py-3 px-4 rounded-xl glass border border-white/10 hover:border-white/20 cursor-pointer transition-all"
          >
            <div class="w-8 h-8 rounded-full bg-rose-500/10 flex items-center justify-center group-hover:scale-110 transition-transform">
              <svg class="w-4 h-4 text-rose-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"
                />
              </svg>
            </div>
            
            <span class="text-sm text-neutral-400 group-hover:text-rose-400">
              {if @uploading, do: "Uploading...", else: "Photo"}
            </span> <.live_file_input upload={@uploads.photo} class="sr-only" />
          </label>
        </form>
         <%!-- Note Button --%>
        <button
          type="button"
          phx-click="open_note_modal"
          class="flex-1 flex items-center justify-center gap-2 py-3 px-4 rounded-xl glass border border-white/10 hover:border-white/20 cursor-pointer transition-all"
        >
          <span class="text-lg text-neutral-400">+</span>
          <span class="text-sm text-neutral-400">Note</span>
        </button> <%!-- Voice Button --%>
        <button
          type="button"
          id="grid-voice-record"
          phx-hook="GridVoiceRecorder"
          data-room-id={@room.id}
          class={"flex-1 flex items-center justify-center gap-2 py-3 px-4 rounded-xl glass border cursor-pointer transition-all #{if @recording_voice, do: "border-red-500 bg-red-500/10", else: "border-white/10 hover:border-white/20"}"}
        >
          <span class={"text-lg #{if @recording_voice, do: "text-red-400", else: "text-neutral-400"}"}>
            {if @recording_voice, do: "●", else: "+"}
          </span>
          <span class={"text-sm #{if @recording_voice, do: "text-red-400", else: "text-neutral-400"}"}>
            {if @recording_voice, do: "Recording...", else: "Voice"}
          </span>
        </button>
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
        class="photo-item opal-shimmer group relative aspect-square overflow-hidden rounded-2xl border border-white/5 hover:border-white/20 cursor-pointer transition-all hover:shadow-xl hover:shadow-violet-500/10 animate-in fade-in zoom-in-95 duration-300"
        phx-click={if Map.get(@item, :content_type) != "audio/encrypted", do: "view_full_image"}
        phx-value-photo_id={@item.id}
      >
        <%= if Map.get(@item, :content_type) == "audio/encrypted" do %>
          <div
            class="w-full h-full flex flex-col items-center justify-center p-4 bg-neutral-900/50 opal-aurora text-center relative z-10"
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
            
            <button class="grid-voice-play-btn w-12 h-12 rounded-full bg-white/10 hover:bg-white/20 flex items-center justify-center text-xl transition-colors mb-3 group-hover:scale-110 active:scale-95 cursor-pointer z-20">
              ▶
            </button>
            <div class="w-full h-1 bg-white/10 rounded-full overflow-hidden">
              <div class="grid-voice-progress h-full bg-emerald-500 w-0 transition-all"></div>
            </div>
            
            <p class="text-xs text-neutral-400 mt-2 font-mono">
              {case Integer.parse(@item.description || "0") do
                {ms, _} -> format_voice_duration(ms)
                _ -> "0:00"
              end}
            </p>
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
         <%!-- Overlay on hover --%>
        <div class="absolute inset-0 bg-gradient-to-t from-black/80 via-black/20 to-transparent opacity-0 group-hover:opacity-100 transition-opacity flex flex-col justify-end p-4">
          <div class="flex items-center gap-2 text-xs">
            <div
              class="w-2 h-2 rounded-full"
              style={"background-color: #{@item.user_color}"}
            />
            <span class="text-neutral-300">
              {@item.user_name || String.slice(@item.user_id, 0, 6)}
            </span> <span class="text-neutral-600">{format_time(@item.uploaded_at)}</span>
          </div>
          
          <%= if @item.description do %>
            <p class="text-neutral-400 text-xs mt-1 line-clamp-2">{@item.description}</p>
          <% end %>
          
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
      </div>
    <% else %>
      <%!-- Note card (clickable to expand) --%>
      <div
        id={@id}
        class="photo-item opal-shimmer group relative aspect-square overflow-hidden rounded-2xl border border-white/5 hover:border-cyan-500/20 transition-all hover:shadow-xl hover:shadow-cyan-500/10 animate-in fade-in zoom-in-95 duration-300 cursor-pointer"
        phx-click="view_note"
        phx-value-note_id={@item.id}
      >
        <div class="w-full h-full p-4 flex flex-col opal-aurora">
          <div class="flex-1 overflow-hidden">
            <p class="text-sm text-neutral-200 line-clamp-6">{@item.content}</p>
          </div>
          
          <div class="mt-2 pt-2 border-t border-white/5">
            <div class="flex items-center gap-2">
              <div
                class="w-5 h-5 rounded-full"
                style={"background-color: #{@item.user_color}"}
              />
              <span class="text-xs text-neutral-500 truncate mobile-only">
                {@item.user_name || String.slice(@item.user_id, 0, 6)}
              </span>
              <span class="text-neutral-600 text-[10px] ml-auto">
                {format_time(@item.inserted_at)}
              </span>
            </div>
          </div>
          
          <%= if @item.user_id == @current_user.id do %>
            <div class="absolute top-2 right-2 opacity-0 group-hover:opacity-100 transition-opacity">
              <button
                type="button"
                phx-click="delete_note"
                phx-value-id={@item.id}
                data-confirm="delete?"
                class="text-neutral-500 hover:text-red-500 text-xs p-1"
              >
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
                  />
                </svg>
              </button>
            </div>
          <% end %>
        </div>
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
