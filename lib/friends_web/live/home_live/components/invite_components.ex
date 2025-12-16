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
      <div 
        class="fixed inset-0 z-[110]" 
        phx-window-keydown="close_invite_modal"
        phx-key="escape"
        role="dialog"
        aria-modal="true"
      >
        <%!-- Backdrop --%>
        <div 
          class="absolute inset-0 bg-black/80 backdrop-blur-sm animate-in fade-in duration-200"
          phx-click="close_invite_modal"
        ></div>

        <%!-- Modal Content --%>
        <div class="absolute inset-0 flex items-center justify-center p-4 pointer-events-none">
          <div 
            class="w-full max-w-lg bg-[#0F0F0F] rounded-2xl shadow-2xl border border-white/10 overflow-hidden pointer-events-auto animate-in zoom-in-95 duration-200 flex flex-col max-h-[90vh]"
          >
            <%!-- Header --%>
            <div class="p-6 border-b border-white/5 bg-white/5 relative">
              <div class="flex items-center justify-between">
                <div>
                  <h2 class="text-xl font-bold text-white tracking-wide">
                    Invite to {if @room, do: @room.name || @room.code, else: "Room"}
                  </h2>
                  <p class="text-neutral-400 text-sm mt-1">Add friends to this private space</p>
                </div>
                <button 
                  phx-click="close_invite_modal"
                  class="text-neutral-500 hover:text-white transition-colors cursor-pointer"
                >
                  <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                  </svg>
                </button>
              </div>
            </div>

            <div class="p-6 overflow-y-auto custom-scrollbar space-y-8">
              <%!-- Section 1: Share Link --%>
              <div class="bg-gradient-to-r from-blue-500/10 to-purple-500/10 rounded-xl p-4 border border-white/5">
                <div class="flex items-center gap-3 mb-3">
                  <div class="w-8 h-8 rounded-full bg-blue-500/20 flex items-center justify-center text-blue-400">
                    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1" />
                    </svg>
                  </div>
                  <h3 class="text-sm font-bold text-white uppercase tracking-wider">Share Invite Link</h3>
                </div>
                
                <div class="flex gap-2">
                  <div class="flex-1 bg-black/50 border border-white/10 rounded-lg px-3 py-2.5 flex items-center shadow-inner">
                    <code class="text-sm text-neutral-300 truncate font-mono select-all">
                      {url(~p"/r/#{@room.code}")}
                    </code>
                  </div>
                  <button
                    phx-hook="CopyToClipboard"
                    data-copy={url(~p"/r/#{@room.code}")}
                    id="invite-copy-btn"
                    class="px-5 bg-white hover:bg-neutral-200 text-black font-bold uppercase tracking-wide text-xs rounded-lg transition-colors cursor-pointer shadow-lg active:scale-95"
                  >
                    Copy
                  </button>
                </div>
                <p class="text-xs text-neutral-500 mt-2 ml-1">Anyone with this link can request to join.</p>
              </div>

              <%!-- Section 2: Direct Invite --%>
              <div>
                <div class="flex items-center gap-3 mb-4">
                  <div class="w-8 h-8 rounded-full bg-emerald-500/20 flex items-center justify-center text-emerald-400">
                    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M18 9v3m0 0v3m0-3h3m-3 0h-3m-2-5a4 4 0 11-8 0 4 4 0 018 0zM3 20a6 6 0 0112 0v1H3v-1z" />
                    </svg>
                  </div>
                  <h3 class="text-sm font-bold text-white uppercase tracking-wider">Add Friends</h3>
                </div>

                <%!-- Search --%>
                <div class="relative mb-4">
                  <svg class="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-neutral-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
                  </svg>
                  <form phx-change="search_member_invite" phx-submit="add_room_member_by_username">
                    <input
                      type="text"
                      name="query"
                      value={@invite_username}
                      autocomplete="off"
                      placeholder="Search friends by name..."
                      class="w-full bg-neutral-900 border border-white/10 rounded-xl py-2.5 pl-10 pr-4 text-sm text-white placeholder-neutral-500 focus:outline-none focus:border-emerald-500/50 focus:ring-1 focus:ring-emerald-500/50"
                    />
                  </form>
                </div>

                <%!-- Friend List --%>
                <div class="border border-white/5 rounded-xl bg-neutral-900/30 overflow-hidden">
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
                    <div class="p-8 text-center">
                      <p class="text-neutral-500 text-sm">
                        <%= if @search_query == "", do: "No friends to invite yet.", else: "No friends found." %>
                      </p>
                      <%= if @search_query == "" do %>
                        <p class="text-neutral-600 text-xs mt-1">Add friends in the Network tab first.</p>
                      <% end %>
                    </div>
                  <% else %>
                    <div class="max-h-64 overflow-y-auto divide-y divide-white/5">
                      <%= for friend <- filtered_friends do %>
                        <div class="flex items-center justify-between p-3 hover:bg-white/5 transition-colors group">
                          <div class="flex items-center gap-3">
                            <div 
                              class="w-10 h-10 rounded-full flex items-center justify-center text-sm font-bold text-white"
                              style={"background-color: #{friend_color(friend.user)}"}
                            >
                              {String.first(friend.user.username)}
                            </div>
                            <div>
                              <p class="text-sm font-bold text-neutral-200">@{friend.user.username}</p>
                            </div>
                          </div>
                          
                          <button
                            phx-click="invite_to_room"
                            phx-value-user_id={friend.user.id}
                            class="px-3 py-1.5 rounded-lg bg-white/10 hover:bg-emerald-500 text-white text-xs font-bold uppercase tracking-wider transition-all cursor-pointer group-hover:shadow-lg"
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
