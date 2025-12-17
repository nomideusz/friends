defmodule FriendsWeb.HomeLive.Components.InviteComponents do
  @moduledoc """
  Components for the Invite System.
  """
  use FriendsWeb, :html
  import FriendsWeb.HomeLive.Helpers

  attr :show, :boolean, default: false
  attr :friends, :list, default: []
  attr :invite_username, :string, default: ""
  attr :room, :map, required: true
  attr :search_query, :string, default: ""

  def invite_modal(assigns) do
    ~H"""
    <%= if @show do %>
      <div class="surface-overlay" style="z-index: 300;">
        <div class="absolute inset-0 bg-black/80 backdrop-blur-md animate-in fade-in duration-200" phx-click="close_invite_modal"></div>

        <div 
          id="invite-modal-container"
          class="surface-island aether-card w-full max-w-lg h-[80vh] md:h-auto flex flex-col shadow-[0_30px_100px_rgba(0,0,0,0.8)] rounded-t-[2rem] rounded-b-none lg:rounded-b-[2rem]"
          phx-window-keydown="close_invite_modal"
          phx-key="escape"
        >
          <div class="sheet-handle" phx-click="close_invite_modal"><div></div></div>
          
          <div class="flex-1 overflow-y-auto">
            <div class="p-8 pb-6 border-b border-white/5 bg-white/5 relative">
              <div class="flex items-center justify-between">
                <div>
                  <h2 class="text-2xl font-bold text-white tracking-tight">
                    Invite to {if @room, do: @room.name || @room.code, else: "Room"}
                  </h2>
                  <p class="text-[10px] font-bold text-white/30 uppercase tracking-widest mt-1">Add friends to this space</p>
                </div>
                <button 
                  phx-click="close_invite_modal"
                  class="w-10 h-10 flex items-center justify-center text-white/30 hover:text-white hover:bg-white/10 rounded-full transition-all cursor-pointer"
                >
                  <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M6 18L18 6M6 6l12 12" />
                  </svg>
                </button>
              </div>
            </div>

            <div class="p-8 overflow-y-auto custom-scrollbar space-y-8">
              <%!-- Section 1: Share Link --%>
              <div class="bg-blue-500/10 rounded-2xl p-6 border border-blue-500/20">
                <div class="flex items-center gap-3 mb-4">
                  <div class="w-8 h-8 rounded-full bg-blue-500/20 flex items-center justify-center text-blue-400">
                    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1" />
                    </svg>
                  </div>
                  <h3 class="text-xs font-bold text-white uppercase tracking-widest">Share Invite Link</h3>
                </div>
                
                <div class="flex gap-2">
                  <div class="flex-1 bg-black/50 border border-white/10 rounded-xl px-4 py-3 flex items-center shadow-inner overflow-hidden">
                    <code class="text-xs text-white/50 truncate font-mono select-all">
                      {url(~p"/r/#{@room.code}")}
                    </code>
                  </div>
                  <button
                    phx-hook="CopyToClipboard"
                    data-copy={url(~p"/r/#{@room.code}")}
                    id="invite-copy-btn"
                    class="btn-aether btn-aether-primary !px-5"
                  >
                    Copy
                  </button>
                </div>
              </div>

              <%!-- Section 2: Direct Invite --%>
              <div class="pb-4">
                <div class="flex items-center gap-3 mb-6">
                  <div class="w-8 h-8 rounded-full bg-emerald-500/20 flex items-center justify-center text-emerald-400">
                    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M18 9v3m0 0v3m0-3h3m-3 0h-3m-2-5a4 4 0 11-8 0 4 4 0 018 0zM3 20a6 6 0 0112 0v1H3v-1z" />
                    </svg>
                  </div>
                  <h3 class="text-xs font-bold text-white uppercase tracking-widest">Add Friends</h3>
                </div>

                <%!-- Search --%>
                <div class="relative mb-6">
                  <input
                    type="text"
                    name="query"
                    value={@invite_username}
                    autocomplete="off"
                    placeholder="Search by name..."
                    class="w-full"
                    phx-change="search_member_invite"
                    phx-submit="add_room_member_by_username"
                  />
                </div>

                <%!-- Friend List --%>
                <div class="rounded-2xl bg-white/5 border border-white/5 overflow-hidden">
                  <%
                    filtered_friends = 
                      if @search_query == "" do
                        @friends
                      else
                        Enum.filter(@friends, fn friend -> 
                          String.contains?(String.downcase(friend.user.username), String.downcase(@search_query))
                        end)
                      end
                  %>
                  <%= if filtered_friends == [] do %>
                    <div class="p-10 text-center">
                      <p class="text-white/20 text-sm font-medium">
                        <%= if @search_query == "", do: "No friends to invite yet.", else: "No friends found." %>
                      </p>
                    </div>
                  <% else %>
                    <div class="max-h-64 overflow-y-auto divide-y divide-white/5 custom-scrollbar">
                      <%= for friend <- filtered_friends do %>
                        <div class="flex items-center justify-between p-4 hover:bg-white/5 transition-colors group">
                          <div class="flex items-center gap-4">
                            <div 
                              class="w-10 h-10 rounded-full flex items-center justify-center text-xs font-bold text-black"
                              style={"background-color: #{friend_color(friend.user)}"}
                            >
                              {String.first(friend.user.username)}
                            </div>
                            <div>
                              <p class="text-sm font-bold text-white">@{friend.user.username}</p>
                            </div>
                          </div>
                          
                          <button
                            phx-click="invite_to_room"
                            phx-value-user_id={friend.user.id}
                            class="px-4 py-2 rounded-xl bg-white/5 hover:bg-white text-white/50 hover:text-black text-xs font-bold uppercase tracking-widest transition-all cursor-pointer"
                          >
                            Add
                          </button>
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    <% end %>
    """
  end
end
