defmodule FriendsWeb.HomeLive.Components.ModalComponents do
  use FriendsWeb, :html
  import FriendsWeb.HomeLive.Helpers

  # --- Photo Modal ---
  attr :show, :boolean, default: false
  attr :photo, :map, default: nil

  def photo_modal(assigns) do
    ~H"""
    <%= if @show and @photo do %>
      <div
        class="fixed inset-0 bg-black/90 backdrop-blur-sm z-[100] flex items-center justify-center p-4"
        phx-window-keydown="close_image_modal"
        phx-key="escape"
      >
        <div
          class="max-w-4xl max-h-[90vh] relative aether-card bg-black/90 p-4 rounded-xl shadow-2xl"
          phx-click-away="close_image_modal"
        >
          <%= if @photo.data do %>
            <img
              src={@photo.data}
              alt="Photo"
              class="max-w-full max-h-[80vh] object-contain rounded-lg shadow-2xl mx-auto"
            />
          <% else %>
            <div class="flex items-center justify-center h-64 w-64 bg-neutral-800 rounded-lg">
              <p class="text-red-500">No image data</p>
            </div>
          <% end %>
          
          <button
            phx-click="close_image_modal"
            class="absolute top-2 right-2 w-10 h-10 bg-black/50 hover:bg-black/80 rounded-full flex items-center justify-center text-white transition-colors cursor-pointer backdrop-blur-md"
          >
            <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M6 18L18 6M6 6l12 12"
              />
            </svg>
          </button>
        </div>
      </div>
    <% end %>
    """
  end

  # --- Note Modal ---
  attr :show, :boolean, default: false
  attr :action, :string, default: "post_feed_note"

  def note_modal(assigns) do
    ~H"""
    <%= if @show do %>
      <div
        class="fixed inset-0 bg-black/60 backdrop-blur-sm z-50 flex items-center justify-center p-4"
      >
        <div class="aether-card w-full max-w-lg rounded-2xl p-6 shadow-2xl bg-black/90" phx-click-away="close_note_modal">
          <h3 class="text-lg font-bold uppercase tracking-wider text-neutral-400 mb-4">
            <%= if @action == "post_feed_note", do: "Create a Public Note", else: "Create a Room Note" %>
          </h3>
          
          <form phx-submit={@action}>
            <textarea
              name="note"
              rows="4"
              class="w-full bg-white border border-neutral-300 rounded md:rounded-lg p-4 text-neutral-900 placeholder-neutral-500 focus:border-opal-rose focus:outline-none resize-none shadow-inner"
              placeholder="What's on your mind?"
              autofocus
            ></textarea>
            <div class="flex justify-end gap-3 mt-4">
              <button
                type="button"
                phx-click="close_note_modal"
                class="px-4 py-2 text-neutral-400 hover:text-white transition-colors cursor-pointer"
              >
                Cancel
              </button>
              <button
                type="submit"
                class="px-6 py-2 bg-cyan-500 hover:bg-cyan-400 text-black font-medium rounded-lg transition-colors cursor-pointer"
              >
                Post
              </button>
            </div>
          </form>
        </div>
      </div>
    <% end %>
    """
  end

  # --- Invite Modal ---
  attr :show, :boolean, default: false
  attr :friends, :list, default: []

  def invite_modal(assigns) do
    ~H"""
    <%= if @show do %>
      <div
        class="fixed inset-0 bg-black/60 backdrop-blur-sm z-50 flex items-center justify-center p-4"
      >
        <div class="aether-card w-full max-w-md rounded-2xl p-6 shadow-2xl bg-black/90" phx-click-away="close_invite_modal">
          <div class="flex items-center justify-between mb-6">
            <h3 class="text-lg font-bold uppercase tracking-wider text-neutral-400">Invite to {@room.name || @room.code}</h3>
            
            <button
              phx-click="close_invite_modal"
              class="text-neutral-400 hover:text-white transition-colors cursor-pointer"
            >
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M6 18L18 6M6 6l12 12"
                />
              </svg>
            </button>
          </div>
          
          <div class="space-y-6">
            <%!-- Copy Link --%>
            <div>
              <label class="block text-xs font-medium text-neutral-400 uppercase tracking-wider mb-2">
                Room Link
              </label>
              <div class="flex gap-2">
                <input
                  type="text"
                  value={url(~p"/r/#{@room.code}")}
                  readonly
                  class="flex-1 px-3 py-2 bg-neutral-100 border border-neutral-300 rounded text-sm text-neutral-600 font-mono select-all focus:outline-none"
                />
                <button
                  id="copy-invite-link"
                  phx-hook="CopyToClipboard"
                  data-copy={url(~p"/r/#{@room.code}")}
                  class="px-3 py-2 bg-neutral-200 hover:bg-neutral-300 text-neutral-900 font-bold uppercase tracking-wider text-xs rounded border border-neutral-300 transition-colors cursor-pointer active:translate-y-px shadow-sm"
                >
                  Copy
                </button>
              </div>
            </div>
             <%!-- Invite User --%>
            <div>
              <label class="block text-xs font-medium text-neutral-400 uppercase tracking-wider mb-2">
                Add Member
              </label>
              <form
                phx-submit="add_room_member"
                phx-change="update_room_invite_username"
                class="flex gap-2 mb-4"
              >
                <input
                  type="text"
                  name="username"
                  value={@invite_username}
                  placeholder="Enter username"
                  class="flex-1 px-3 py-2 bg-white border border-neutral-300 rounded text-sm text-neutral-900 placeholder-neutral-500 focus:outline-none focus:border-opal-rose"
                  autocomplete="off"
                />
                <button
                  type="submit"
                  class="px-4 py-2 bg-cyan-500 hover:bg-cyan-400 text-black text-sm font-medium rounded-lg transition-colors cursor-pointer"
                >
                  Add
                </button>
              </form>
              
              <%= if @friends != [] do %>
                <div class="mt-4 border-t border-neutral-200 pt-4">
                   <label class="block text-xs font-medium text-neutral-500 uppercase tracking-wider mb-2">
                    Quick Add
                  </label>
                  <div class="space-y-2 max-h-40 overflow-y-auto pr-2">
                    <%= for friend <- @friends do %>
                      <div class="flex items-center justify-between p-2 rounded hover:bg-neutral-800 group transition-colors">
                        <div class="flex items-center gap-2">
                          <div
                            class="w-6 h-6 rounded-full flex items-center justify-center text-[10px] font-bold text-white relative z-10"
                            style={"background-color: #{friend_color(friend.user)}"}
                          >
                            {String.first(friend.user.username)}
                          </div>
                          <span class="text-sm text-neutral-300">@{friend.user.username}</span>
                        </div>
                        
                        <button
                          type="button"
                          phx-click="add_room_member"
                          phx-value-username={friend.user.username}
                          class="text-xs text-cyan-500 hover:text-cyan-400 opacity-0 group-hover:opacity-100 transition-all font-medium"
                        >
                          Add +
                        </button>
                      </div>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    <% end %>
    """
  end
end
