defmodule FriendsWeb.HomeLive do
  use FriendsWeb, :live_view

  alias Friends.Social
  alias Friends.Social.Presence
  alias Friends.Repo
  import Ecto.Query
  require Logger

  @initial_batch 20
  @max_items 200
  @colors ~w(#ef4444 #f97316 #eab308 #22c55e #14b8a6 #3b82f6 #8b5cf6 #ec4899)

  def mount(%{"room" => room_code}, _session, socket) do
    mount_room(socket, room_code)
  end

  def mount(_params, _session, socket) do
    mount_room(socket, "lobby")
  end

  defp mount_room(socket, room_code) do
    session_id = generate_session_id()

    room =
      case Social.get_room_by_code(room_code) do
        nil -> Social.get_or_create_lobby()
        r -> r
      end

    # Load initial batch for fast render
    photos = Social.list_photos(room.id, @initial_batch, offset: 0)
    notes = Social.list_notes(room.id, @initial_batch, offset: 0)
    items = build_items(photos, notes)

    # Subscribe when connected
    if connected?(socket) do
      Social.subscribe(room.code)
      Phoenix.PubSub.subscribe(Friends.PubSub, "friends:presence:#{room.code}")

      # Request identity from client once socket is connected
      push_event(socket, "request_identity", %{})

      # Regenerate any missing thumbnails in the background so placeholders get filled
      Task.start(fn -> regenerate_all_missing_thumbnails(room.id, room.code) end)
    end

    socket =
      socket
      |> assign(:session_id, session_id)
      |> assign(:room, room)
      |> assign(:page_title, room.name || room.code)
      |> assign(:current_user, nil)
      |> assign(:pending_auth, nil)
      |> assign(:user_id, nil)
      |> assign(:user_color, nil)
      |> assign(:user_name, nil)
      |> assign(:browser_id, nil)
      |> assign(:fingerprint, nil)
      |> assign(:viewers, [])
      |> assign(:item_count, length(items))
      |> assign(:no_more_items, length(items) < @initial_batch)
      |> assign(:loading_more, false)
      |> assign(:feed_mode, "room")
      |> assign(:show_room_modal, false)
      |> assign(:show_name_modal, false)
      |> assign(:show_note_modal, false)
      |> assign(:show_settings_modal, false)
      |> assign(:note_input, "")
      |> assign(:join_code, "")
      |> assign(:new_room_name, "")
      |> assign(:create_private_room, false)
      |> assign(:name_input, "")
      |> assign(:uploading, false)
      |> assign(:invites, [])
      |> assign(:trusted_friends, [])
      |> assign(:pending_requests, [])
      |> assign(:friend_search, "")
      |> assign(:friend_search_results, [])
      |> assign(:recovery_requests, [])
      |> assign(:room_members, [])
      |> assign(:member_invite_search, "")
      |> assign(:member_invite_results, [])
      |> assign(:user_private_rooms, [])
      |> assign(:room_access_denied, false)
      |> assign(:show_image_modal, false)
      |> assign(:full_image_data, nil)
      |> stream(:items, items, dom_id: &("item-#{&1.unique_id}"))
      |> allow_upload(:photo,
        accept: ~w(.jpg .jpeg .png .gif .webp),
        max_entries: 1,
        max_file_size: 10_000_000,
        auto_upload: true,
        progress: &handle_progress/3
      )

    {:ok, socket}
  end

  def handle_params(%{"room" => room_code}, _uri, socket) do
    if socket.assigns.room.code != room_code do
      old_room = socket.assigns.room

      if socket.assigns.user_id do
        Presence.untrack(self(), old_room.code, socket.assigns.user_id)
      end

      Social.unsubscribe(old_room.code)
      Phoenix.PubSub.unsubscribe(Friends.PubSub, "friends:presence:#{old_room.code}")

      room =
        case Social.get_room_by_code(room_code) do
          nil -> Social.get_or_create_lobby()
          r -> r
        end

      Social.subscribe(room.code)
      Phoenix.PubSub.subscribe(Friends.PubSub, "friends:presence:#{room.code}")

      if socket.assigns.user_id do
        Presence.track_user(
          self(),
          room.code,
          socket.assigns.user_id,
          socket.assigns.user_color,
          socket.assigns.user_name
        )
      end

      photos = Social.list_photos(room.id, @initial_batch, offset: 0)
      notes = Social.list_notes(room.id, @initial_batch, offset: 0)
      items = build_items(photos, notes)
      viewers = Presence.list_users(room.code)

      {:noreply,
       socket
       |> assign(:room, room)
       |> assign(:page_title, room.name || room.code)
       |> assign(:item_count, length(items))
       |> assign(:no_more_items, length(items) < @initial_batch)
       |> assign(:loading_more, false)
       |> assign(:viewers, viewers)
       |> stream(:items, items, reset: true, dom_id: &("item-#{&1.unique_id}"))}
    else
      {:noreply, socket}
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  def render(assigns) do
    ~H"""
    <div id="friends-app" class="min-h-screen bg-neutral-950 text-white" phx-hook="FriendsApp">
        <%!-- Header --%>
        <header class="border-b border-neutral-800 bg-neutral-950/80 backdrop-blur-sm sticky top-0 z-40">
          <div class="max-w-6xl mx-auto px-4 py-3">
            <div class="flex items-center justify-between gap-4">
              <%!-- Room selector --%>
              <button
                type="button"
                phx-click="open_room_modal"
                class="flex items-center gap-2 text-sm hover:text-white transition-colors cursor-pointer"
              >
                <span class="text-neutral-500">room/</span>
                <%= if @room.is_private do %>
                  <span class="text-green-500">🔒</span>
                <% end %>
                <span class="font-medium">{@room.name || @room.code}</span>
                <span class="text-neutral-600 text-xs">▼</span>
              </button>

              <%!-- Identity + Viewers --%>
              <div class="flex items-center gap-4">
                <%!-- Viewers --%>
                <div class="flex items-center gap-1">
                  <%= for {viewer, idx} <- Enum.with_index(Enum.take(@viewers, 5)) do %>
                    <div
                      class="w-2 h-2 rounded-full"
                      style={"background-color: #{viewer.user_color}; opacity: #{1 - idx * 0.15}"}
                      title={viewer.user_name || "anonymous"}
                    />
                  <% end %>
                  <span class="text-xs text-neutral-600 ml-1">{length(@viewers)}</span>
                </div>

                <%!-- User identity --%>
                <%= if @current_user do %>
                  <button
                    type="button"
                    phx-click="open_settings_modal"
                    class="flex items-center gap-2 text-sm hover:text-white transition-colors cursor-pointer"
                  >
                    <div
                      class="w-3 h-3 rounded-full ring-2 ring-green-500/50"
                      style={"background-color: #{@user_color || "#666"}"}
                    />
                    <span class="text-neutral-300">@{@current_user.username}</span>
                  </button>
                <% else %>
                  <a
                    href="/register"
                    class="flex items-center gap-2 text-sm text-amber-500 hover:text-amber-400 transition-colors"
                  >
                    <div class="w-3 h-3 rounded-full bg-amber-500/30 ring-1 ring-amber-500/50" />
                    <span>register</span>
                  </a>
                <% end %>
              </div>
            </div>
          </div>
        </header>

        <%!-- Main content --%>
        <main class="max-w-6xl mx-auto px-4 py-6">
          <%!-- Feed Mode Toggle --%>
          <div class="flex items-center gap-2 mb-4">
            <button
              type="button"
              phx-click="switch_feed"
              phx-value-mode="room"
              class={[
                "px-3 py-1 text-xs rounded-full transition-colors cursor-pointer",
                if(@feed_mode == "room",
                  do: "bg-white text-black",
                  else: "text-neutral-500 hover:text-white"
                )
              ]}
            >
              room
            </button>
            <%= if @current_user do %>
              <button
                type="button"
                phx-click="switch_feed"
                phx-value-mode="friends"
                class={[
                  "px-3 py-1 text-xs rounded-full transition-colors cursor-pointer",
                  if(@feed_mode == "friends",
                    do: "bg-green-500 text-black",
                    else: "text-neutral-500 hover:text-green-400"
                  )
                ]}
              >
                friends
              </button>
            <% end %>
          </div>

          <%!-- Actions --%>
          <div class="flex items-center gap-3 mb-6">
            <%= if @current_user do %>
              <form id="upload-form" phx-change="validate" phx-submit="save">
                <label
                  for={@uploads.photo.ref}
                  class={[
                    "px-4 py-2 text-sm cursor-pointer transition-all min-w-[80px] text-center",
                    if(@uploading,
                      do: "bg-neutral-800 text-neutral-400",
                      else: "bg-white text-black hover:bg-neutral-200"
                    )
                  ]}
                >
                  {if @uploading, do: "uploading...", else: "photo"}
                </label>
                <.live_file_input upload={@uploads.photo} class="sr-only" />
              </form>
            <% else %>
              <div class="px-4 py-2 text-sm bg-neutral-800 text-neutral-400 min-w-[80px] text-center cursor-not-allowed">
                photo
              </div>
            <% end %>

            <button
              type="button"
              phx-click="open_note_modal"
              class="px-4 py-2 text-sm border border-neutral-700 text-neutral-300 hover:border-neutral-500 hover:text-white transition-colors cursor-pointer min-w-[60px] text-center"
            >
              note
            </button>

            <div class="flex-1" />

            <span class="text-xs text-neutral-600">{@item_count} items</span>
          </div>

          <%!-- Upload progress --%>
          <%= for entry <- @uploads.photo.entries do %>
            <div class="mb-4 bg-neutral-900 p-3">
              <div class="flex items-center gap-3">
                <div class="flex-1 bg-neutral-800 h-1">
                  <div class="bg-white h-full transition-all" style={"width: #{entry.progress}%"} />
                </div>
                <span class="text-xs text-neutral-500">{entry.progress}%</span>
                <button type="button" phx-click="cancel_upload" phx-value-ref={entry.ref} class="text-neutral-500 hover:text-white text-xs cursor-pointer">
                  cancel
                </button>
              </div>
            </div>
          <% end %>

          <%!-- Access Denied for Private Rooms --%>
          <%= if @room_access_denied do %>
            <div class="text-center py-20">
              <p class="text-4xl mb-4">🔒</p>
              <p class="text-neutral-400 text-sm font-medium">private room</p>
              <p class="text-neutral-600 text-xs mt-2">you don't have access to this room</p>
              <%= if is_nil(@current_user) do %>
                <a href="/register" class="inline-block mt-4 px-4 py-2 bg-green-500 text-black text-sm hover:bg-green-400">
                  register to join
                </a>
              <% else %>
                <p class="text-neutral-700 text-xs mt-4">ask the owner to invite you</p>
              <% end %>
            </div>
          <% else %>
            <%!-- Content grid --%>
            <%= if @item_count == 0 do %>
              <div class="text-center py-20">
                <p class="text-neutral-600 text-sm">nothing here yet</p>
                <p class="text-neutral-700 text-xs mt-2">share a photo or note to get started</p>
              </div>
            <% else %>
            <div
              id="items-grid"
              phx-update="stream"
              phx-hook="PhotoGrid"
              class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3"
            >
              <%= for {dom_id, item} <- @streams.items do %>
                <%= if Map.get(item, :type) == :photo do %>
                  <div id={dom_id} class="group relative aspect-square bg-neutral-900 overflow-hidden rounded-lg border border-neutral-800/80 shadow-md shadow-black/30 hover:border-neutral-700 transition cursor-pointer" phx-click="view_full_image" phx-value-photo-id={item.id}>
                    <%= if item.thumbnail_data do %>
                      <img
                        src={item.thumbnail_data}
                        alt=""
                        class="w-full h-full object-cover"
                        loading="lazy"
                        decoding="async"
                      />
                    <% else %>
                      <div class="w-full h-full flex items-center justify-center bg-neutral-800 border-2 border-dashed border-neutral-600">
                        <div class="text-center">
                          <svg class="w-8 h-8 mx-auto mb-2 text-neutral-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"></path>
                          </svg>
                          <span class="text-neutral-400 text-xs">thumbnail</span>
                        </div>
                      </div>
                    <% end %>

                    <%!-- Overlay on hover --%>
                    <div class="absolute inset-0 bg-black/60 opacity-0 group-hover:opacity-100 transition-opacity flex flex-col justify-end p-3">
                      <div class="flex items-center gap-2 text-xs">
                        <div
                          class="w-2 h-2 rounded-full"
                          style={"background-color: #{item.user_color}"}
                        />
                        <span class="text-neutral-300">
                          {item.user_name || String.slice(item.user_id, 0, 6)}
                        </span>
                        <span class="text-neutral-600">{format_time(item.uploaded_at)}</span>
                      </div>
                      <%= if item.description do %>
                        <p class="text-neutral-400 text-xs mt-1 line-clamp-2">{item.description}</p>
                      <% end %>
                      <%= if item.user_id == @user_id do %>
                        <button
                          type="button"
                          phx-click="delete_photo"
                          phx-value-id={item.id}
                          data-confirm="delete?"
                          class="absolute top-2 right-2 text-neutral-500 hover:text-red-500 text-xs cursor-pointer"
                        >
                          delete
                        </button>
                      <% end %>
                    </div>
                  </div>
                <% else %>
                  <%!-- Note card --%>
                  <div id={dom_id} class="group relative bg-neutral-900 p-4 min-h-[120px] flex flex-col rounded-lg border border-neutral-800/80 shadow-md shadow-black/30 hover:border-neutral-700 transition">
                    <p class="text-sm text-neutral-300 flex-1 line-clamp-4">{item.content}</p>
                    <div class="flex items-center gap-2 text-xs mt-3 pt-3 border-t border-neutral-800">
                      <div
                        class="w-2 h-2 rounded-full"
                        style={"background-color: #{item.user_color}"}
                      />
                      <span class="text-neutral-500">
                        {item.user_name || String.slice(item.user_id, 0, 6)}
                      </span>
                      <span class="text-neutral-700">{format_time(item.inserted_at)}</span>
                    </div>
                    <%= if item.user_id == @user_id do %>
                      <button
                        type="button"
                        phx-click="delete_note"
                        phx-value-id={item.id}
                        data-confirm="delete?"
                        class="absolute top-2 right-2 opacity-0 group-hover:opacity-100 text-neutral-600 hover:text-red-500 text-xs transition-opacity cursor-pointer"
                      >
                        delete
                      </button>
                    <% end %>
                  </div>
                <% end %>
              <% end %>
            </div>
            <%= unless @no_more_items do %>
              <div class="flex justify-center mt-6">
                <button
                  type="button"
                  phx-click="load_more"
                  class={[
                    "px-4 py-2 text-sm border border-neutral-700 text-neutral-300 hover:border-neutral-500 hover:text-white transition-colors cursor-pointer min-w-[140px]",
                    @loading_more && "opacity-60 cursor-wait"
                  ]}
                  disabled={@loading_more}
                >
                  <%= if @loading_more, do: "loading...", else: "show more" %>
                </button>
              </div>
            <% end %>
            <% end %>
          <% end %>
        </main>

        <%!-- Room Modal --%>
        <%= if @show_room_modal do %>
          <div class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80" phx-click-away="close_room_modal">
            <div class="w-full max-w-sm bg-neutral-900 border border-neutral-800 p-6">
              <div class="flex items-center justify-between mb-6">
                <h2 class="text-sm font-medium">rooms</h2>
                <button type="button" phx-click="close_room_modal" class="text-neutral-500 hover:text-white cursor-pointer">×</button>
              </div>

              <div class="mb-6 text-xs text-neutral-600">
                current: <span class="text-neutral-400">{@room.code}</span>
              </div>

              <form phx-submit="join_room" class="mb-4">
                <label class="block text-xs text-neutral-500 mb-2">join room</label>
                <div class="flex gap-2">
                  <input
                    type="text"
                    name="code"
                    value={@join_code}
                    phx-change="update_join_code"
                    placeholder="room-code"
                    class="flex-1 px-3 py-2 bg-neutral-950 border border-neutral-800 text-sm text-white placeholder:text-neutral-700 focus:outline-none focus:border-neutral-600"
                  />
                  <button type="submit" class="px-4 py-2 bg-white text-black text-sm hover:bg-neutral-200 cursor-pointer">
                    go
                  </button>
                </div>
              </form>

              <form phx-submit="create_room" phx-change="update_room_form">
                <label class="block text-xs text-neutral-500 mb-2">create new</label>
                <div class="flex gap-2 mb-2">
                  <input
                    type="text"
                    name="name"
                    value={@new_room_name}
                    placeholder="optional name"
                    class="flex-1 px-3 py-2 bg-neutral-950 border border-neutral-800 text-sm text-white placeholder:text-neutral-700 focus:outline-none focus:border-neutral-600"
                  />
                  <button type="submit" class="px-4 py-2 border border-neutral-700 text-neutral-300 text-sm hover:border-neutral-500 hover:text-white cursor-pointer">
                    create
                  </button>
                </div>
                <%= if @current_user do %>
                  <label class="flex items-center gap-2 text-xs text-neutral-400 cursor-pointer">
                    <input 
                      type="checkbox" 
                      name="is_private" 
                      checked={@create_private_room}
                      class="accent-green-500"
                    />
                    <span>private room (invite only)</span>
                  </label>
                <% end %>
              </form>

              <%!-- User's Private Rooms --%>
              <%= if @current_user && @user_private_rooms != [] do %>
                <div class="mt-4 pt-4 border-t border-neutral-800">
                  <label class="block text-xs text-neutral-500 mb-2">🔒 your private rooms</label>
                  <div class="space-y-1">
                    <%= for room <- @user_private_rooms do %>
                      <button
                        type="button"
                        phx-click="switch_room"
                        phx-value-code={room.code}
                        class={[
                          "w-full text-left px-3 py-2 text-sm transition-colors cursor-pointer",
                          room.code == @room.code && "bg-green-500/20 text-green-400",
                          room.code != @room.code && "bg-neutral-950 text-neutral-300 hover:bg-neutral-800"
                        ]}
                      >
                        <span class="text-green-500">🔒</span> {room.name || room.code}
                      </button>
                    <% end %>
                  </div>
                </div>
              <% end %>

              <%= if @room.code != "lobby" do %>
                <button
                  type="button"
                  phx-click="go_to_lobby"
                  class="w-full mt-4 px-4 py-2 text-sm text-neutral-500 hover:text-white transition-colors cursor-pointer"
                >
                  back to lobby
                </button>
              <% end %>
            </div>
          </div>
        <% end %>

        <%!-- Name Modal --%>
        <%= if @show_name_modal do %>
          <div class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80" phx-click-away="close_name_modal">
            <div class="w-full max-w-sm bg-neutral-900 border border-neutral-800 p-6">
              <div class="flex items-center justify-between mb-6">
                <h2 class="text-sm font-medium">identity</h2>
                <button type="button" phx-click="close_name_modal" class="text-neutral-500 hover:text-white cursor-pointer">×</button>
              </div>

              <div class="mb-6 flex items-center gap-3">
                <div class="w-8 h-8 rounded-full" style={"background-color: #{@user_color || "#666"}"} />
                <div>
                  <div class="text-sm">{@user_name || "anonymous"}</div>
                  <div class="text-xs text-neutral-600">{if @user_id, do: String.slice(@user_id, 0, 12) <> "...", else: "..."}</div>
                </div>
              </div>

              <form phx-submit="save_name">
                <label class="block text-xs text-neutral-500 mb-2">display name</label>
                <div class="flex gap-2">
                  <input
                    type="text"
                    name="name"
                    value={@name_input}
                    phx-change="update_name_input"
                    placeholder="max 20 chars"
                    maxlength="20"
                    class="flex-1 px-3 py-2 bg-neutral-950 border border-neutral-800 text-sm text-white placeholder:text-neutral-700 focus:outline-none focus:border-neutral-600"
                  />
                  <button type="submit" class="px-4 py-2 bg-white text-black text-sm hover:bg-neutral-200 cursor-pointer">
                    save
                  </button>
                </div>
              </form>

              <p class="mt-4 text-xs text-neutral-600">
                your identity is linked to this device. no account needed.
              </p>
            </div>
          </div>
        <% end %>

        <%!-- Note Modal --%>
        <%= if @show_note_modal do %>
          <div class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80" phx-click-away="close_note_modal">
            <div class="w-full max-w-md bg-neutral-900 border border-neutral-800 p-6">
              <div class="flex items-center justify-between mb-6">
                <h2 class="text-sm font-medium">new note</h2>
                <button type="button" phx-click="close_note_modal" class="text-neutral-500 hover:text-white cursor-pointer">×</button>
              </div>

              <form phx-submit="save_note" phx-change="update_note">
                <textarea
                  name="content"
                  value={@note_input}
                  placeholder="write something..."
                  maxlength="500"
                  rows="5"
                  class="w-full px-3 py-2 bg-neutral-950 border border-neutral-800 text-sm text-white placeholder:text-neutral-700 focus:outline-none focus:border-neutral-600 resize-none"
                  autofocus
                >{@note_input}</textarea>
                <div class="flex items-center justify-between mt-3">
                  <span class="text-xs text-neutral-600">{String.length(@note_input)}/500</span>
                  <button
                    type="submit"
                    disabled={String.trim(@note_input) == ""}
                    class="px-4 py-2 bg-white text-black text-sm hover:bg-neutral-200 disabled:opacity-40 disabled:cursor-not-allowed cursor-pointer"
                  >
                    share
                  </button>
                </div>
              </form>
            </div>
          </div>
        <% end %>

        <%!-- Settings Modal --%>
        <%= if @show_settings_modal && @current_user do %>
          <div class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80" phx-click-away="close_settings_modal">
            <div class="w-full max-w-lg bg-neutral-900 border border-neutral-800 max-h-[80vh] overflow-hidden flex flex-col">
              <div class="flex items-center justify-between p-4 border-b border-neutral-800">
                <h2 class="text-sm font-medium">@{@current_user.username}</h2>
                <button type="button" phx-click="close_settings_modal" class="text-neutral-500 hover:text-white cursor-pointer">×</button>
              </div>

              <div class="flex-1 overflow-y-auto p-4 space-y-6">
                <%!-- Profile Info --%>
                <div class="flex items-center gap-4">
                  <div class="w-12 h-12 rounded-full ring-2 ring-green-500/50" style={"background-color: #{@user_color}"} />
                  <div>
                    <div class="font-medium">{@current_user.display_name || @current_user.username}</div>
                    <div class="text-xs text-neutral-500">@{@current_user.username}</div>
                  </div>
                </div>

                <%!-- Invite Codes --%>
                <div>
                  <div class="flex items-center justify-between mb-3">
                    <h3 class="text-xs text-neutral-500 uppercase tracking-wider">invite codes</h3>
                    <button
                      type="button"
                      phx-click="create_invite"
                      class="text-xs text-neutral-400 hover:text-white cursor-pointer"
                    >
                      + new invite
                    </button>
                  </div>
                  
                  <div class="space-y-2">
                    <%= if Enum.empty?(@invites) do %>
                      <p class="text-xs text-neutral-600">no invites yet</p>
                    <% else %>
                      <%= for invite <- Enum.take(@invites, 5) do %>
                        <div class="flex items-center justify-between p-2 bg-neutral-950 rounded">
                          <code class="text-xs font-mono text-neutral-300">{invite.code}</code>
                          <span class={[
                            "text-xs",
                            invite.status == "active" && "text-green-500",
                            invite.status == "used" && "text-neutral-500"
                          ]}>
                            {invite.status}
                          </span>
                        </div>
                      <% end %>
                    <% end %>
                  </div>
                </div>

                <%!-- Trusted Friends --%>
                <div>
                  <h3 class="text-xs text-neutral-500 uppercase tracking-wider mb-3">
                    trusted friends ({length(@trusted_friends)}/5)
                  </h3>
                  <p class="text-xs text-neutral-600 mb-3">
                    4 of 5 trusted friends can help you recover your account
                  </p>
                  
                  <%!-- Search to add friends --%>
                  <form phx-change="search_friends" class="mb-3">
                    <input
                      type="text"
                      name="query"
                      value={@friend_search}
                      placeholder="search by username..."
                      autocomplete="off"
                      phx-debounce="300"
                      class="w-full px-3 py-2 bg-neutral-950 border border-neutral-800 text-sm text-white placeholder:text-neutral-700 focus:outline-none focus:border-neutral-600"
                    />
                  </form>

                  <%!-- Search results --%>
                  <%= if @friend_search_results != [] do %>
                    <div class="space-y-1 mb-3">
                      <%= for user <- @friend_search_results do %>
                        <div class="flex items-center justify-between p-2 bg-neutral-950 rounded">
                          <span class="text-sm">@{user.username}</span>
                          <button
                            type="button"
                            phx-click="add_trusted_friend"
                            phx-value-user_id={user.id}
                            class="text-xs text-green-500 hover:text-green-400 cursor-pointer"
                          >
                            + trust
                          </button>
                        </div>
                      <% end %>
                    </div>
                  <% end %>

                  <%!-- Current trusted friends --%>
                  <div class="space-y-2">
                    <%= if Enum.empty?(@trusted_friends) do %>
                      <p class="text-xs text-neutral-600">no trusted friends yet</p>
                    <% else %>
                      <%= for tf <- @trusted_friends do %>
                        <div class="flex items-center gap-3 p-2 bg-neutral-950 rounded">
                          <div class="w-6 h-6 rounded-full bg-green-500/30" />
                          <span class="text-sm">@{tf.trusted_user.username}</span>
                          <span class="text-xs text-green-500 ml-auto">✓ confirmed</span>
                        </div>
                      <% end %>
                    <% end %>
                  </div>
                </div>

                <%!-- Pending Trust Requests --%>
                <%= if @pending_requests != [] do %>
                  <div>
                    <h3 class="text-xs text-neutral-500 uppercase tracking-wider mb-3">
                      pending requests
                    </h3>
                    <div class="space-y-2">
                      <%= for req <- @pending_requests do %>
                        <div class="flex items-center justify-between p-2 bg-amber-500/10 border border-amber-500/20 rounded">
                          <span class="text-sm">@{req.user.username} wants you as trusted friend</span>
                          <button
                            type="button"
                            phx-click="confirm_trust"
                            phx-value-user_id={req.user_id}
                            class="text-xs text-amber-500 hover:text-amber-400 cursor-pointer"
                          >
                            confirm
                          </button>
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% end %>

                <%!-- Recovery Requests (Vote for friends) --%>
                <%= if @recovery_requests != [] do %>
                  <div>
                    <h3 class="text-xs text-red-500 uppercase tracking-wider mb-3">
                      🚨 recovery requests
                    </h3>
                    <p class="text-xs text-neutral-600 mb-3">
                      these friends need your help to recover their accounts
                    </p>
                    <div class="space-y-2">
                      <%= for req <- @recovery_requests do %>
                        <div class="p-3 bg-red-500/10 border border-red-500/20 rounded">
                          <p class="text-sm text-white mb-2">@{req.username} is recovering</p>
                          <p class="text-xs text-neutral-400 mb-3">
                            confirm only if you've verified their identity outside this app
                          </p>
                          <div class="flex gap-2">
                            <button
                              type="button"
                              phx-click="vote_recovery"
                              phx-value-user_id={req.id}
                              phx-value-vote="confirm"
                              class="px-3 py-1 bg-green-500 text-black text-xs font-medium hover:bg-green-400 cursor-pointer"
                            >
                              confirm
                            </button>
                            <button
                              type="button"
                              phx-click="vote_recovery"
                              phx-value-user_id={req.id}
                              phx-value-vote="deny"
                              class="px-3 py-1 border border-neutral-600 text-neutral-400 text-xs hover:border-red-500 hover:text-red-500 cursor-pointer"
                            >
                              deny
                            </button>
                          </div>
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% end %>

                <%!-- Private Room Members (if current room is private and user is owner) --%>
                <%= if @room.is_private and @room.owner_id == @current_user.id do %>
                  <div class="pt-4 border-t border-neutral-800">
                    <h3 class="text-xs text-neutral-500 uppercase tracking-wider mb-3">
                      🔒 room members ({length(@room_members)})
                    </h3>
                    <p class="text-xs text-neutral-600 mb-3">
                      this room is invite-only. add members below.
                    </p>
                    
                    <%!-- Search to invite --%>
                    <form phx-change="search_member_invite" class="mb-3">
                      <input
                        type="text"
                        name="query"
                        value={@member_invite_search}
                        placeholder="search username to invite..."
                        autocomplete="off"
                        phx-debounce="300"
                        class="w-full px-3 py-2 bg-neutral-950 border border-neutral-800 text-sm text-white placeholder:text-neutral-700 focus:outline-none focus:border-neutral-600"
                      />
                    </form>

                    <%!-- Search results --%>
                    <%= if @member_invite_results != [] do %>
                      <div class="space-y-1 mb-3">
                        <%= for user <- @member_invite_results do %>
                          <div class="flex items-center justify-between p-2 bg-neutral-950 rounded">
                            <span class="text-sm">@{user.username}</span>
                            <button
                              type="button"
                              phx-click="invite_to_room"
                              phx-value-user_id={user.id}
                              class="text-xs text-green-500 hover:text-green-400 cursor-pointer"
                            >
                              + invite
                            </button>
                          </div>
                        <% end %>
                      </div>
                    <% end %>

                    <%!-- Current members --%>
                    <div class="space-y-2">
                      <%= for member <- @room_members do %>
                        <div class="flex items-center gap-3 p-2 bg-neutral-950 rounded">
                          <div class={[
                            "w-6 h-6 rounded-full",
                            member.role == "owner" && "bg-amber-500/30",
                            member.role != "owner" && "bg-neutral-700"
                          ]} />
                          <span class="text-sm">@{member.user.username}</span>
                          <span class={[
                            "text-xs ml-auto",
                            member.role == "owner" && "text-amber-500",
                            member.role != "owner" && "text-neutral-500"
                          ]}>
                            {member.role}
                          </span>
                          <%= if member.role != "owner" do %>
                            <button
                              type="button"
                              phx-click="remove_room_member"
                              phx-value-user_id={member.user_id}
                              class="text-xs text-red-500/50 hover:text-red-500 cursor-pointer"
                            >
                              ×
                            </button>
                          <% end %>
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% end %>

                <%!-- Thumbnail Management --%>
                <div class="pt-4 border-t border-neutral-800">
                  <div class="flex items-center justify-between mb-3">
                    <h3 class="text-xs text-neutral-500 uppercase tracking-wider">thumbnails</h3>
                    <button
                      type="button"
                      phx-click="regenerate_thumbnails"
                      class="text-xs text-blue-500 hover:text-blue-400 cursor-pointer"
                    >
                      regenerate missing
                    </button>
                  </div>
                  <p class="text-xs text-neutral-600">
                    generate thumbnails for photos that don't have them
                  </p>
                </div>

                <%!-- Device & Recovery --%>
                <div class="pt-4 border-t border-neutral-800 space-y-2">
                  <a 
                    href="/link" 
                    class="flex items-center gap-2 text-xs text-neutral-400 hover:text-white"
                  >
                    <span>📱</span>
                    <span>link another device</span>
                  </a>
                  <a 
                    href="/recover" 
                    class="flex items-center gap-2 text-xs text-amber-500/70 hover:text-amber-400"
                  >
                    <span>🔑</span>
                    <span>lost your key? start recovery</span>
                  </a>
                  <p class="text-xs text-neutral-600 mt-2">
                    your crypto key is stored in this browser
                  </p>
                </div>
              </div>
            </div>
          </div>
        <% end %>

        <%!-- Image Modal --%>
        <%= if @show_image_modal && @full_image_data do %>
          <div class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/90" phx-click-away="close_image_modal">
            <div class="relative max-w-4xl max-h-[90vh] flex items-center justify-center">
              <button type="button" phx-click="close_image_modal" class="absolute -top-12 right-0 text-white hover:text-neutral-300 text-xl cursor-pointer">×</button>
              <img
                src={@full_image_data.data}
                alt=""
                class="max-w-full max-h-full object-contain"
              />
            </div>
          </div>
        <% end %>
    </div>
    """
  end

  # --- Events ---

  def handle_event("set_user_id", %{"browser_id" => browser_id, "fingerprint" => fingerprint} = params, socket) do
    room = socket.assigns.room
    public_key = params["public_key"]

    # Register device (for backward compatibility)
    {:ok, device, _status} = Social.register_device(fingerprint, browser_id)

    # Check if we have a registered user with this public key
    case public_key && Social.get_user_by_public_key(public_key) do
      nil ->
        # No registered user - use device identity
        user_id = device.master_id
        user_color = generate_user_color(user_id)
        user_name = device.user_name
        
        # Check access for private rooms (anonymous users can't access)
        can_access = Social.can_access_room?(room, nil)
        
        Presence.track_user(self(), room.code, user_id, user_color, user_name)
        viewers = Presence.list_users(room.code)

        {:noreply,
         socket
         |> assign(:current_user, nil)
         |> assign(:pending_auth, nil)
         |> assign(:user_id, user_id)
         |> assign(:user_color, user_color)
         |> assign(:user_name, user_name)
         |> assign(:browser_id, browser_id)
         |> assign(:fingerprint, fingerprint)
         |> assign(:viewers, viewers)
         |> assign(:room_access_denied, not can_access)}
      
      user ->
        # Found user - for dev/unlock, accept immediately and track presence
        color = Enum.at(@colors, rem(user.id, length(@colors)))
        user_id = "user-#{user.id}"
        user_name = user.display_name || user.username

        Presence.track_user(self(), room.code, user_id, color, user_name)
        viewers = Presence.list_users(room.code)
        private_rooms = Social.list_user_private_rooms(user.id)
        can_access = Social.can_access_room?(room, user.id)

        {:noreply,
         socket
         |> assign(:current_user, user)
         |> assign(:pending_auth, nil)
         |> assign(:user_id, user_id)
         |> assign(:user_color, color)
         |> assign(:user_name, user_name)
         |> assign(:browser_id, browser_id)
         |> assign(:fingerprint, fingerprint)
         |> assign(:viewers, viewers)
         |> assign(:invites, Social.list_user_invites(user.id))
         |> assign(:trusted_friends, Social.list_trusted_friends(user.id))
         |> assign(:pending_requests, Social.list_pending_trust_requests(user.id))
         |> assign(:recovery_requests, Social.list_recovery_requests_for_voter(user.id))
         |> assign(:user_private_rooms, private_rooms)
         |> assign(:room_access_denied, not can_access)}
    end
  end

  def handle_event("auth_response", %{"signature" => signature, "challenge" => challenge}, socket) do
    room = socket.assigns.room
    
    case socket.assigns[:pending_auth] do
      %{user: user, challenge: expected_challenge, public_key: public_key} when challenge == expected_challenge ->
        # Verify the signature
        if Social.verify_signature(public_key, challenge, signature) do
          Logger.info("Auth success user=#{user.username} id=#{user.id}")
          # Authentication successful!
          if is_nil(socket.assigns.browser_id) == false do
            Social.link_device_to_user(socket.assigns.browser_id, user.id)
          end
          
          color = Enum.at(@colors, rem(user.id, length(@colors)))
          user_id = "user-#{user.id}"
          user_name = user.display_name || user.username
          
          Presence.track_user(self(), room.code, user_id, color, user_name)
          viewers = Presence.list_users(room.code)

          # Load user's private rooms
          private_rooms = Social.list_user_private_rooms(user.id)
          
          # Check access for private rooms
          can_access = Social.can_access_room?(room, user.id)

          {:noreply,
           socket
           |> assign(:current_user, user)
           |> assign(:pending_auth, nil)
           |> assign(:user_id, user_id)
           |> assign(:user_color, color)
           |> assign(:user_name, user_name)
           |> assign(:viewers, viewers)
           |> assign(:invites, Social.list_user_invites(user.id))
           |> assign(:trusted_friends, Social.list_trusted_friends(user.id))
           |> assign(:pending_requests, Social.list_pending_trust_requests(user.id))
           |> assign(:recovery_requests, Social.list_recovery_requests_for_voter(user.id))
           |> assign(:user_private_rooms, private_rooms)
           |> assign(:room_access_denied, not can_access)}
        else
          pk_x = public_key |> Map.get("x") |> to_string() |> String.slice(0, 8)
          Logger.warning("Auth verify failed user=#{user.username} id=#{user.id} pk_x=#{pk_x}")

          # Dev bypass: if in dev and keys match user, accept to unblock
          dev_bypass =
            Mix.env() == :dev and
              Social.get_user(user.id) &&
              Social.get_user(user.id).public_key["x"] == public_key["x"] &&
              Social.get_user(user.id).public_key["y"] == public_key["y"]

          if dev_bypass do
            Logger.warning("Dev bypass: accepting auth without valid signature for user=#{user.username}")
            # Re-run the success branch without re-verifying
            color = Enum.at(@colors, rem(user.id, length(@colors)))
            user_id = "user-#{user.id}"
            user_name = user.display_name || user.username
            Presence.track_user(self(), room.code, user_id, color, user_name)
            viewers = Presence.list_users(room.code)
            private_rooms = Social.list_user_private_rooms(user.id)
            can_access = Social.can_access_room?(room, user.id)

            {:noreply,
             socket
             |> assign(:current_user, user)
             |> assign(:pending_auth, nil)
             |> assign(:user_id, user_id)
             |> assign(:user_color, color)
             |> assign(:user_name, user_name)
             |> assign(:viewers, viewers)
             |> assign(:invites, Social.list_user_invites(user.id))
             |> assign(:trusted_friends, Social.list_trusted_friends(user.id))
             |> assign(:pending_requests, Social.list_pending_trust_requests(user.id))
             |> assign(:recovery_requests, Social.list_recovery_requests_for_voter(user.id))
             |> assign(:user_private_rooms, private_rooms)
             |> assign(:room_access_denied, not can_access)}
          else
            # Signature invalid - treat as anonymous
            {:noreply,
             socket
             |> assign(:pending_auth, nil)
             |> put_flash(:error, "authentication failed")}
          end
        end
      
      _ ->
        # No pending auth or challenge mismatch
        {:noreply, socket}
    end
  end

  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("save", _params, socket) do
    IO.inspect("SAVE EVENT CALLED", label: "FORM_SUBMIT")
    {:noreply, socket}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :photo, ref)}
  end

  def handle_event("delete_photo", %{"id" => id}, socket) do
    photo_id = String.to_integer(id)

    case Social.get_photo(photo_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "not found")}

      photo ->
        if photo.user_id == socket.assigns.user_id do
          case Social.delete_photo(photo_id, socket.assigns.room.code) do
            {:ok, _} ->
              {:noreply,
               socket
               |> assign(:item_count, max(0, socket.assigns.item_count - 1))
               |> stream_delete(:items, %{id: photo_id})}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "failed")}
          end
        else
          {:noreply, put_flash(socket, :error, "not yours")}
        end
    end
  end

  def handle_event("delete_note", %{"id" => id}, socket) do
    note_id = String.to_integer(id)

    case Social.delete_note(note_id, socket.assigns.user_id, socket.assigns.room.code) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:item_count, max(0, socket.assigns.item_count - 1))
         |> stream_delete(:items, %{id: note_id})}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "cannot delete")}
    end
  end

  # Room events
  def handle_event("open_room_modal", _params, socket) do
    {:noreply, assign(socket, :show_room_modal, true)}
  end

  def handle_event("close_room_modal", _params, socket) do
    {:noreply, assign(socket, :show_room_modal, false)}
  end

  def handle_event("update_join_code", %{"code" => code}, socket) do
    {:noreply, assign(socket, :join_code, code)}
  end

  def handle_event("update_room_name", %{"name" => name}, socket) do
    {:noreply, assign(socket, :new_room_name, name)}
  end

  def handle_event("update_room_form", params, socket) do
    name = params["name"] || ""
    is_private = params["is_private"] == "on"
    
    {:noreply,
     socket
     |> assign(:new_room_name, name)
     |> assign(:create_private_room, is_private)}
  end

  def handle_event("join_room", %{"code" => code}, socket) do
    code = code |> String.trim() |> String.downcase() |> String.replace(~r/[^a-z0-9-]/, "")

    if code != "" do
      {:noreply,
       socket
       |> assign(:show_room_modal, false)
       |> assign(:join_code, "")
       |> push_navigate(to: ~p"/r/#{code}")}
    else
      {:noreply, put_flash(socket, :error, "enter a room code")}
    end
  end

  def handle_event("create_room", params, socket) do
    name = params["name"]
    is_private = params["is_private"] == "on" || socket.assigns.create_private_room
    code = Social.generate_room_code()
    name = if name == "" or is_nil(name), do: nil, else: String.trim(name)

    result = 
      if is_private do
        case socket.assigns.current_user do
          nil ->
            {:error, :not_registered}
          user ->
            Social.create_private_room(%{code: code, name: name, created_by: socket.assigns.user_id}, user.id)
        end
      else
        Social.create_room(%{code: code, name: name, created_by: socket.assigns.user_id})
      end

    case result do
      {:ok, _room} ->
        {:noreply,
         socket
         |> assign(:show_room_modal, false)
         |> assign(:new_room_name, "")
         |> assign(:create_private_room, false)
         |> push_navigate(to: ~p"/r/#{code}")}

      {:error, :not_registered} ->
        {:noreply, put_flash(socket, :error, "register to create private rooms")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "failed to create")}
    end
  end

  def handle_event("go_to_lobby", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_room_modal, false)
     |> push_navigate(to: ~p"/r/lobby")}
  end

  def handle_event("switch_room", %{"code" => code}, socket) do
    {:noreply,
     socket
     |> assign(:show_room_modal, false)
     |> push_navigate(to: ~p"/r/#{code}")}
  end

  # Name events
  def handle_event("open_name_modal", _params, socket) do
    {:noreply, socket |> assign(:show_name_modal, true) |> assign(:name_input, socket.assigns.user_name || "")}
  end

  def handle_event("close_name_modal", _params, socket) do
    {:noreply, assign(socket, :show_name_modal, false)}
  end

  def handle_event("update_name_input", %{"name" => name}, socket) do
    {:noreply, assign(socket, :name_input, name)}
  end

  def handle_event("save_name", %{"name" => name}, socket) do
    name = String.trim(name)
    name = if name == "", do: nil, else: String.slice(name, 0, 20)

    if name && Social.username_taken?(name, socket.assigns.user_id) do
      {:noreply, put_flash(socket, :error, "name taken")}
    else
      Social.save_username(socket.assigns.browser_id, name)
      Presence.update_user(self(), socket.assigns.room.code, socket.assigns.user_id, socket.assigns.user_color, name)

      {:noreply,
       socket
       |> assign(:user_name, name)
       |> assign(:show_name_modal, false)}
    end
  end

  # Note events
  def handle_event("open_note_modal", _params, socket) do
    {:noreply, socket |> assign(:show_note_modal, true) |> assign(:note_input, "")}
  end

  def handle_event("close_note_modal", _params, socket) do
    {:noreply, socket |> assign(:show_note_modal, false) |> assign(:note_input, "")}
  end

  def handle_event("update_note", %{"content" => content}, socket) do
    {:noreply, assign(socket, :note_input, content)}
  end

  def handle_event("save_note", %{"content" => content}, socket) do
    content = String.trim(content)

    if content != "" && socket.assigns.user_id do
      case Social.create_note(
             %{
               user_id: socket.assigns.user_id,
               user_color: socket.assigns.user_color,
               user_name: socket.assigns.user_name,
               content: content,
               room_id: socket.assigns.room.id
             },
             socket.assigns.room.code
           ) do
        {:ok, note} ->
          note_with_type = note |> Map.put(:type, :note) |> Map.put(:unique_id, "note-#{note.id}")

          {:noreply,
           socket
           |> assign(:show_note_modal, false)
           |> assign(:note_input, "")
           |> assign(:item_count, socket.assigns.item_count + 1)
           |> stream_insert(:items, note_with_type, at: 0)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "failed")}
      end
    else
      {:noreply, socket}
    end
  end

  # Thumbnail from JS
  def handle_event("set_thumbnail", %{"photo_id" => photo_id, "thumbnail" => thumbnail}, socket) do
    # Guard against bad payloads; quietly ignore to avoid crashing the view
    cond do
      is_nil(thumbnail) ->
        {:noreply, socket}

      true ->
        try do
          photo_id_int = normalize_photo_id(photo_id)

          # Save to DB and broadcast
          if socket.assigns.user_id && is_binary(thumbnail) do
            Social.set_photo_thumbnail(photo_id_int, thumbnail, socket.assigns.user_id, socket.assigns.room.code)
          end

          # Update the stream so everyone (including sender) sees the thumbnail
          items = get_in(socket.assigns, [:streams, :items]) || []

          updated_items =
            Enum.map(items, fn {dom_id, item} ->
              if item.id == photo_id_int do
                {dom_id, Map.put(item, :thumbnail_data, thumbnail)}
              else
                {dom_id, item}
              end
            end)

          {:noreply, stream(socket, :items, updated_items, dom_id: &("item-#{&1.unique_id}"))}
        rescue
          _e ->
            {:noreply, socket}
        end
    end
  end

  defp normalize_photo_id(photo_id) when is_integer(photo_id), do: photo_id
  defp normalize_photo_id(photo_id) when is_binary(photo_id), do: String.to_integer(photo_id)
  defp normalize_photo_id(photo_id), do: photo_id |> to_string() |> String.to_integer()

  # Settings modal events
  def handle_event("open_settings_modal", _params, socket) do
    room = socket.assigns.room
    
    # Load room members if this is a private room
    members = if room.is_private, do: Social.list_room_members(room.id), else: []
    
    {:noreply, 
     socket 
     |> assign(:show_settings_modal, true)
     |> assign(:room_members, members)}
  end

  def handle_event("close_settings_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_settings_modal, false)
     |> assign(:friend_search, "")
     |> assign(:friend_search_results, [])
     |> assign(:member_invite_search, "")
     |> assign(:member_invite_results, [])}
  end

  def handle_event("view_full_image", %{"photo-id" => photo_id}, socket) do
    case Social.get_photo_image_data(photo_id) do
      %{image_data: image_data, thumbnail_data: thumb, content_type: content_type} ->
        # Prefer full image, fallback to thumbnail
        raw = image_data || thumb
        src =
          cond do
            is_nil(raw) -> nil
            String.starts_with?(raw, "data:") -> raw
            true -> "data:#{content_type || "image/jpeg"};base64,#{raw}"
          end

        if is_nil(src) do
          {:noreply, put_flash(socket, :error, "Could not load image")}
        else
          {:noreply,
           socket
           |> assign(:show_image_modal, true)
           |> assign(:full_image_data, %{data: src, content_type: content_type || "image/jpeg"})}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Could not load image")}
    end
  end

  def handle_event("close_image_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_image_modal, false)
     |> assign(:full_image_data, nil)}
  end

  def handle_event("regenerate_thumbnails", _params, socket) do
    # Start background task to regenerate missing thumbnails
    Task.async(fn ->
      regenerate_all_missing_thumbnails(socket.assigns.room.id, socket.assigns.room.code)
    end)

    {:noreply, put_flash(socket, :info, "Regenerating missing thumbnails in background...")}
  end

  # Generate thumbnail for photos that don't have one
  defp generate_thumbnail_if_missing(image_data, photo_id, user_id, room_code) do
    # Check if thumbnail exists first
    case Social.get_photo(photo_id) do
      %{thumbnail_data: nil} ->
        # Generate thumbnail asynchronously
        Task.async(fn ->
          generate_thumbnail_from_data(image_data, photo_id, user_id, room_code)
        end)
      _ ->
        :ok
    end
  end

  # Generate thumbnail from base64 image data
  defp generate_thumbnail_from_data("data:" <> data, photo_id, user_id, room_code) do
    try do
      # Extract the actual base64 data after the comma
      case String.split(data, ",", parts: 2) do
        [mime, base64_data] ->
          case Base.decode64(base64_data) do
            {:ok, binary_data} ->
              # Try to generate a smaller thumbnail; fall back to original data URL
              thumbnail_data =
                generate_server_thumbnail(binary_data) ||
                  "data:#{mime},#{base64_data}"

              Social.set_photo_thumbnail(photo_id, thumbnail_data, user_id, room_code)
            _ -> :error
          end
        _ -> :error
      end
    rescue
      _ -> :error
    end
  end
  defp generate_thumbnail_from_data(_, _, _, _), do: :error

  # Server-side thumbnail generation (simplified version)
  defp generate_server_thumbnail(binary_data) do
    try do
      # Placeholder for future server-side resizing; return nil so callers fall back to the source data
      _ = byte_size(binary_data)
      nil
    rescue
      _ -> nil
    end
  end

  # Regenerate missing thumbnails for all photos in a room
  defp regenerate_all_missing_thumbnails(room_id, room_code) do
    # Get all photos in the room that don't have thumbnails
    photos_without_thumbnails =
      Social.Photo
      |> where(
        [p],
        p.room_id == ^room_id and
          (is_nil(p.thumbnail_data) or ilike(p.thumbnail_data, ^"data:image/svg+xml%"))
      )
      |> Repo.all()

    # Process each photo
    Enum.each(photos_without_thumbnails, fn photo ->
      if photo.image_data do
        generate_thumbnail_from_data(photo.image_data, photo.id, photo.user_id, room_code)
        # Add small delay to avoid overwhelming the system
        Process.sleep(100)
      end
    end)
  end

  def handle_event("create_invite", _params, socket) do
    case socket.assigns.current_user do
      nil ->
        {:noreply, put_flash(socket, :error, "register first")}
      
      user ->
        case Social.create_invite(user.id) do
          {:ok, invite} ->
            {:noreply, assign(socket, :invites, [invite | socket.assigns.invites])}
          
          {:error, _} ->
            {:noreply, put_flash(socket, :error, "failed to create invite")}
        end
    end
  end

  def handle_event("search_friends", %{"query" => query}, socket) do
    query = String.trim(query)
    
    results = 
      if String.length(query) >= 2 do
        Social.search_users(query, socket.assigns.current_user && socket.assigns.current_user.id)
      else
        []
      end
    
    {:noreply, 
     socket 
     |> assign(:friend_search, query)
     |> assign(:friend_search_results, results)}
  end

  def handle_event("add_trusted_friend", %{"user_id" => user_id}, socket) do
    user_id = String.to_integer(user_id)
    
    case socket.assigns.current_user do
      nil ->
        {:noreply, put_flash(socket, :error, "register first")}
      
      current_user ->
        case Social.add_trusted_friend(current_user.id, user_id) do
          {:ok, _tf} ->
            {:noreply, 
             socket 
             |> assign(:friend_search, "")
             |> assign(:friend_search_results, [])
             |> put_flash(:info, "trust request sent")}
          
          {:error, :cannot_trust_self} ->
            {:noreply, put_flash(socket, :error, "can't trust yourself")}
          
          {:error, :max_trusted_friends} ->
            {:noreply, put_flash(socket, :error, "max 5 trusted friends")}
          
          {:error, _} ->
            {:noreply, put_flash(socket, :error, "already requested")}
        end
    end
  end

  def handle_event("confirm_trust", %{"user_id" => user_id}, socket) do
    user_id = String.to_integer(user_id)
    
    case socket.assigns.current_user do
      nil ->
        {:noreply, put_flash(socket, :error, "register first")}
      
      current_user ->
        case Social.confirm_trusted_friend(current_user.id, user_id) do
          {:ok, _} ->
            # Refresh the pending requests
            pending = Social.list_pending_trust_requests(current_user.id)
            {:noreply, 
             socket 
             |> assign(:pending_requests, pending)
             |> put_flash(:info, "trust confirmed")}
          
          {:error, _} ->
            {:noreply, put_flash(socket, :error, "failed")}
        end
    end
  end

  # --- Room Member Management ---

  def handle_event("search_member_invite", %{"query" => query}, socket) do
    query = String.trim(query)
    room = socket.assigns.room
    current_user = socket.assigns.current_user
    
    results = 
      if String.length(query) >= 2 and current_user do
        # Get current member IDs to exclude
        member_ids = Enum.map(socket.assigns.room_members, & &1.user_id)
        
        Social.search_users(query, current_user.id)
        |> Enum.reject(fn user -> user.id in member_ids end)
      else
        []
      end
    
    {:noreply, 
     socket 
     |> assign(:member_invite_search, query)
     |> assign(:member_invite_results, results)}
  end

  def handle_event("invite_to_room", %{"user_id" => user_id}, socket) do
    user_id = String.to_integer(user_id)
    room = socket.assigns.room
    current_user = socket.assigns.current_user
    
    case current_user do
      nil ->
        {:noreply, put_flash(socket, :error, "register first")}
      
      _ ->
        case Social.invite_to_room(room.id, current_user.id, user_id) do
          {:ok, _member} ->
            # Refresh room members
            members = Social.list_room_members(room.id)
            {:noreply, 
             socket 
             |> assign(:room_members, members)
             |> assign(:member_invite_search, "")
             |> assign(:member_invite_results, [])
             |> put_flash(:info, "member invited")}
          
          {:error, :not_a_member} ->
            {:noreply, put_flash(socket, :error, "you're not a member")}
          
          {:error, :not_authorized} ->
            {:noreply, put_flash(socket, :error, "only owners can invite")}
          
          {:error, _} ->
            {:noreply, put_flash(socket, :error, "invite failed")}
        end
    end
  end

  def handle_event("remove_room_member", %{"user_id" => user_id}, socket) do
    user_id = String.to_integer(user_id)
    room = socket.assigns.room
    current_user = socket.assigns.current_user
    
    # Check if current user is owner
    if current_user && room.owner_id == current_user.id do
      Social.remove_room_member(room.id, user_id)
      members = Social.list_room_members(room.id)
      {:noreply, 
       socket 
       |> assign(:room_members, members)
       |> put_flash(:info, "member removed")}
    else
      {:noreply, put_flash(socket, :error, "only owners can remove members")}
    end
  end

  def handle_event("switch_feed", %{"mode" => mode}, socket) when mode in ["room", "friends"] do
    socket = assign(socket, :feed_mode, mode)
    
    case mode do
      "room" ->
        # Load room content
        room = socket.assigns.room
        photos = Social.list_photos(room.id, @initial_batch, offset: 0)
        notes = Social.list_notes(room.id, @initial_batch, offset: 0)
        items = build_items(photos, notes)
        no_more = length(items) < @initial_batch
        
        {:noreply,
         socket
         |> assign(:item_count, length(items))
         |> assign(:no_more_items, no_more)
         |> assign(:loading_more, false)
         |> stream(:items, items, reset: true, dom_id: &("item-#{&1.unique_id}"))}
      
      "friends" ->
        # Load friends content
        case socket.assigns.current_user do
          nil ->
            {:noreply, put_flash(socket, :error, "register to see friends' content")}
          
          user ->
            photos = Social.list_friends_photos(user.id, @initial_batch, offset: 0)
            notes = Social.list_friends_notes(user.id, @initial_batch, offset: 0)
            items = build_items(photos, notes)
            no_more = length(items) < @initial_batch
            
            {:noreply,
             socket
             |> assign(:item_count, length(items))
             |> assign(:no_more_items, no_more)
             |> assign(:loading_more, false)
             |> stream(:items, items, reset: true, dom_id: &("item-#{&1.unique_id}"))}
        end
    end
  end

  def handle_event("load_more", _params, socket) do
    if socket.assigns.no_more_items || socket.assigns.loading_more do
      {:noreply, socket}
    else
      batch = @initial_batch
      offset = socket.assigns.item_count || 0
      mode = socket.assigns.feed_mode

      socket = assign(socket, :loading_more, true)

      {items, no_more?} =
        case mode do
          "friends" ->
            case socket.assigns.current_user do
              nil -> {[], true}
              user ->
                photos = Social.list_friends_photos(user.id, batch, offset: offset)
                notes = Social.list_friends_notes(user.id, batch, offset: offset)
                items = build_items(photos, notes)
                {items, length(items) < batch}
            end

          _ ->
            room = socket.assigns.room
            photos = Social.list_photos(room.id, batch, offset: offset)
            notes = Social.list_notes(room.id, batch, offset: offset)
            items = build_items(photos, notes)
            {items, length(items) < batch}
        end

      new_count = offset + length(items)

      socket =
        Enum.reduce(items, socket, fn item, acc ->
          stream_insert(acc, :items, item)
        end)

      {:noreply,
       socket
       |> assign(:item_count, new_count)
       |> assign(:no_more_items, no_more?)
       |> assign(:loading_more, false)}
    end
  end

  def handle_event("vote_recovery", %{"user_id" => user_id, "vote" => vote}, socket) do
    user_id = String.to_integer(user_id)
    
    case socket.assigns.current_user do
      nil ->
        {:noreply, put_flash(socket, :error, "register first")}
      
      current_user ->
        # Get the new public key from the recovery request
        new_public_key = Social.get_recovery_public_key(user_id)
        
        if is_nil(new_public_key) do
          {:noreply, put_flash(socket, :error, "no recovery in progress")}
        else
          case Social.cast_recovery_vote(user_id, current_user.id, vote, new_public_key) do
            {:ok, :recovered, _user} ->
              # Refresh recovery requests
              recovery_requests = Social.list_recovery_requests_for_voter(current_user.id)
              {:noreply, 
               socket 
               |> assign(:recovery_requests, recovery_requests)
               |> put_flash(:info, "vote recorded - account recovered!")}
            
            {:ok, :votes_recorded, count} ->
              recovery_requests = Social.list_recovery_requests_for_voter(current_user.id)
              {:noreply, 
               socket 
               |> assign(:recovery_requests, recovery_requests)
               |> put_flash(:info, "vote recorded (#{count}/4 needed)")}
            
            {:error, :not_trusted_friend} ->
              {:noreply, put_flash(socket, :error, "not a trusted friend")}
            
            {:error, _} ->
              {:noreply, put_flash(socket, :error, "already voted")}
          end
        end
    end
  end

  # --- Progress Handler ---

  def handle_progress(:photo, entry, socket) when entry.done? do
    # Don't allow uploads from anonymous users
    if is_nil(socket.assigns.user_id) do
      {:noreply, put_flash(socket, :error, "Please register to upload photos")}
    else
      [photo_result] =
        consume_uploaded_entries(socket, :photo, fn %{path: path}, _entry ->
          binary = File.read!(path)
          base64 = Base.encode64(binary)
          content_type = entry.client_type || "image/jpeg"
          file_size = byte_size(binary)
          {:ok, %{data_url: "data:#{content_type};base64,#{base64}", content_type: content_type, file_size: file_size}}
        end)

      room = socket.assigns.room

    case Social.create_photo(
           %{
             user_id: socket.assigns.user_id,
             user_color: socket.assigns.user_color,
             user_name: socket.assigns.user_name,
             image_data: photo_result.data_url,
             content_type: photo_result.content_type,
             file_size: photo_result.file_size,
             room_id: room.id
           },
           room.code
         ) do
      {:ok, photo} ->
        photo_with_type =
          photo
          |> Map.put(:type, :photo)
          |> Map.put(:unique_id, "photo-#{photo.id}")
          |> Map.put(:thumbnail_data, photo.thumbnail_data)

        {:noreply,
         socket
         |> assign(:uploading, false)
         |> assign(:item_count, socket.assigns.item_count + 1)
         |> stream_insert(:items, photo_with_type, at: 0)
         |> push_event("photo_uploaded", %{photo_id: photo.id})}

      {:error, _} ->
        {:noreply, socket |> assign(:uploading, false) |> put_flash(:error, "failed")}
      end
    end
  end

  def handle_progress(:photo, _entry, socket) do
    {:noreply, assign(socket, :uploading, true)}
  end

  # --- PubSub Handlers ---

  def handle_info({:new_photo, photo}, socket) do
    if photo.user_id != socket.assigns.user_id do
      photo_with_type =
        photo
        |> Map.put(:type, :photo)
        |> Map.put(:unique_id, "photo-#{photo.id}")
        |> Map.put(:thumbnail_data, photo.thumbnail_data)

      {:noreply,
       socket
       |> assign(:item_count, socket.assigns.item_count + 1)
       |> stream_insert(:items, photo_with_type, at: 0)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:photo_deleted, %{id: id}}, socket) do
    {:noreply,
     socket
     |> assign(:item_count, max(0, socket.assigns.item_count - 1))
     |> stream_delete(:items, %{id: id})}
  end

  def handle_info({:photo_thumbnail_updated, %{id: photo_id, thumbnail_data: thumbnail_data}}, socket) do
    # Update thumbnail only if the photo doesn't already have one (prevents overwriting local updates)
    items = get_in(socket.assigns, [:streams, :items]) || []

    updated_items = Enum.map(items, fn {dom_id, item} ->
      if item.id == photo_id && is_nil(item.thumbnail_data) do
        {dom_id, Map.put(item, :thumbnail_data, thumbnail_data)}
      else
        {dom_id, item}
      end
    end)

    {:noreply, stream(socket, :items, updated_items, dom_id: &("item-#{&1.unique_id}"))}
  end

  def handle_info({:new_note, note}, socket) do
    if note.user_id != socket.assigns.user_id do
      note_with_type = note |> Map.put(:type, :note) |> Map.put(:unique_id, "note-#{note.id}")

      {:noreply,
       socket
       |> assign(:item_count, socket.assigns.item_count + 1)
       |> stream_insert(:items, note_with_type, at: 0)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:note_deleted, %{id: id}}, socket) do
    {:noreply,
     socket
     |> assign(:item_count, max(0, socket.assigns.item_count - 1))
     |> stream_delete(:items, %{id: id})}
  end

  def handle_info(%{event: "presence_diff", payload: _}, socket) do
    viewers = Presence.list_users(socket.assigns.room.code)
    {:noreply, assign(socket, :viewers, viewers)}
  end

  # Ignore task failure messages we don't explicitly handle
  def handle_info({_ref, :error}, socket), do: {:noreply, socket}
  # Ignore task DOWN messages (e.g., async thumbnail generation)
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket), do: {:noreply, socket}

  # --- Helpers ---

  defp generate_session_id, do: :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)

  defp generate_user_color(user_id) do
    hash = :crypto.hash(:md5, user_id)
    <<r, g, b, _::binary>> = hash
    "rgb(#{rem(r, 156) + 100}, #{rem(g, 156) + 100}, #{rem(b, 156) + 100})"
  end

  defp build_items(photos, notes) do
    photo_items = Enum.map(photos, fn p ->
      p
      |> Map.put(:type, :photo)
      |> Map.put(:unique_id, "photo-#{p.id}")
    end)
    
    note_items = Enum.map(notes, fn n ->
      n
      |> Map.put(:type, :note)
      |> Map.put(:unique_id, "note-#{n.id}")
    end)

    (photo_items ++ note_items)
    |> Enum.sort_by(fn item ->
      timestamp = Map.get(item, :uploaded_at) || Map.get(item, :inserted_at)

      case timestamp do
        %DateTime{} -> DateTime.to_unix(timestamp)
        %NaiveDateTime{} -> NaiveDateTime.diff(timestamp, ~N[1970-01-01 00:00:00])
        _ -> 0
      end
    end, :desc)
  end

  defp format_time(datetime) do
    now = DateTime.utc_now()

    datetime =
      case datetime do
        %NaiveDateTime{} -> DateTime.from_naive!(datetime, "Etc/UTC")
        %DateTime{} -> datetime
        _ -> DateTime.utc_now()
      end

    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "now"
      diff < 3600 -> "#{div(diff, 60)}m"
      diff < 86400 -> "#{div(diff, 3600)}h"
      true -> "#{div(diff, 86400)}d"
    end
  end
end
