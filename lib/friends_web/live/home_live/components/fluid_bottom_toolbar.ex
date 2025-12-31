defmodule FriendsWeb.HomeLive.Components.FluidBottomToolbar do
  @moduledoc """
  Unified bottom toolbar that adapts based on context.
  Feed context: inline search bar
  Room context: room-specific action buttons
  """
  use FriendsWeb, :html
  import FriendsWeb.HomeLive.Helpers

  # ============================================================================
  # BOTTOM TOOLBAR
  # Context-aware adaptive toolbar
  # Context: :feed, :room, :focused
  # ============================================================================

  attr :context, :atom, default: :feed  # :feed, :room, :focused
  attr :current_user, :map, required: true
  attr :room, :map, default: nil
  attr :show_chat, :boolean, default: true
  attr :unread_count, :integer, default: 0
  attr :online_friend_count, :integer, default: 0
  attr :pending_request_count, :integer, default: 0
  attr :search_query, :string, default: ""
  attr :search_results, :map, default: %{people: [], groups: [], actions: []}

  def bottom_toolbar(assigns) do
    ~H"""
    <div class="fixed bottom-0 inset-x-0 z-[100] pointer-events-none pb-safe">
      <div class="flex justify-center px-4 pb-4">
        <%= case @context do %>
          <% :feed -> %>
            <%!-- Feed context: inline search bar --%>
            <div class="pointer-events-auto w-full max-w-lg relative">
              <%!-- Search Results Panel --%>
              <%= if @search_query != "" do %>
                <div class={[
                  "absolute bottom-full mb-4 inset-x-0 max-h-[60vh] overflow-y-auto custom-scrollbar",
                  "bg-neutral-900/90 backdrop-blur-2xl border border-white/10 rounded-[2rem] shadow-2xl",
                  "animate-in fade-in slide-in-from-bottom-4 duration-300 ease-out p-4 space-y-6"
                ]}>
                  <%!-- Actions --%>
                  <%= if length(@search_results.actions) > 0 do %>
                    <.result_section title="Actions" icon="zap">
                      <%= for action <- @search_results.actions do %>
                        <.action_result action={action} />
                      <% end %>
                    </.result_section>
                  <% end %>

                  <%!-- People --%>
                  <%= if length(@search_results.people) > 0 do %>
                    <.result_section title="People" icon="user">
                      <%= for person <- @search_results.people do %>
                        <.person_result person={person} />
                      <% end %>
                    </.result_section>
                  <% end %>

                  <%!-- Groups --%>
                  <%= if length(@search_results.groups) > 0 do %>
                    <.result_section title="Groups" icon="users">
                      <%= for group <- @search_results.groups do %>
                        <.group_result group={group} />
                      <% end %>
                    </.result_section>
                  <% end %>

                  <%!-- Empty State --%>
                  <%= if length(@search_results.people) == 0 and length(@search_results.groups) == 0 and length(@search_results.actions) == 0 do %>
                    <div class="text-center py-8 text-white/30">
                      <p class="text-sm">No results for "{@search_query}"</p>
                      <p class="text-xs mt-1">Try @username, #group, or /command</p>
                    </div>
                  <% end %>
                </div>
              <% end %>

              <form phx-change="toolbar_search" phx-submit="toolbar_search_submit" class="relative">
                <div class="flex items-center gap-2 px-4 py-3 bg-neutral-900/40 backdrop-blur-xl rounded-2xl shadow-2xl">
                  
                  <%!-- Search input --%>
                  <input
                    type="text"
                    name="query"
                    value={@search_query}
                    placeholder="Search people, groups..."
                    phx-debounce="300"
                    autocomplete="off"
                    class="flex-1 bg-transparent border-none outline-none text-white placeholder:text-white/40 text-sm"
                  />
                  
                  <%!-- Clear button --%>
                  <%= if @search_query != "" do %>
                    <button
                      type="button"
                      phx-click="clear_toolbar_search"
                      class="text-white/40 hover:text-white/70 transition-colors cursor-pointer"
                    >
                      <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                      </svg>
                    </button>
                  <% end %>
                </div>
              </form>
            </div>
          <% :room -> %>
            <%!-- Room context: room-specific actions only --%>
            <nav class="pointer-events-auto flex items-center gap-1 px-2 py-2 bg-neutral-900/90 backdrop-blur-xl border border-white/10 rounded-2xl shadow-2xl">
              <%= if @room && @room.room_type != "dm" do %>
                <.toolbar_button icon="people" label="Members" event="toggle_members_panel" />
              <% end %>
              <.toolbar_button icon="plus" label="Add" event="toggle_add_menu" />
            </nav>
          <% :focused -> %>
            <nav class="pointer-events-auto flex items-center gap-1 px-2 py-2 bg-neutral-900/90 backdrop-blur-xl border border-white/10 rounded-2xl shadow-2xl">
              <.toolbar_button icon="back" label="Back" event="close_focused_view" />
              <.toolbar_button icon="heart" label="React" event="react_to_item" />
              <.toolbar_button icon="reply" label="Reply" event="reply_to_item" />
              <.toolbar_button icon="more" label="More" event="show_item_actions" />
            </nav>
          <% _ -> %>
            <%!-- Fallback: same as feed --%>
            <div class="pointer-events-auto w-full max-w-lg">
              <div class="flex items-center gap-2 px-4 py-3 bg-neutral-900/40 backdrop-blur-xl rounded-2xl shadow-2xl">
                <input
                  type="text"
                  name="query"
                  placeholder="Search people, groups..."
                  class="flex-1 bg-transparent border-none outline-none text-white placeholder:text-white/40 text-sm"
                />
              </div>
            </div>
        <% end %>
      </div>
    </div>
    """
  end

  # ============================================================================
  # TOOLBAR BUTTON
  # ============================================================================

  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :event, :string, required: true
  attr :badge, :integer, default: 0
  attr :active, :boolean, default: false

  defp toolbar_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={@event}
      class={[
        "relative flex flex-col items-center justify-center w-16 h-14 rounded-xl transition-all cursor-pointer",
        @active && "bg-white/10",
        not @active && "hover:bg-white/5"
      ]}
    >
      <div class="relative">
        <.toolbar_icon name={@icon} active={@active} />
        <%= if @badge > 0 do %>
          <span class="absolute -top-1 -right-2 min-w-[18px] h-[18px] flex items-center justify-center text-[10px] font-bold bg-blue-500 text-white rounded-full px-1">
            <%= if @badge > 99, do: "99+", else: @badge %>
          </span>
        <% end %>
      </div>
      <span class={[
        "text-[10px] mt-1 font-medium",
        @active && "text-white",
        not @active && "text-white/50"
      ]}>
        {@label}
      </span>
    </button>
    """
  end

  # ============================================================================
  # TOOLBAR ICONS
  # ============================================================================

  attr :name, :string, required: true
  attr :active, :boolean, default: false

  defp toolbar_icon(%{name: "search"} = assigns) do
    ~H"""
    <svg class={icon_class(@active)} fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
    </svg>
    """
  end

  defp toolbar_icon(%{name: "plus"} = assigns) do
    ~H"""
    <svg class={icon_class(@active)} fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
    </svg>
    """
  end

  defp toolbar_icon(%{name: "chat"} = assigns) do
    ~H"""
    <svg class={icon_class(@active)} fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z" />
    </svg>
    """
  end

  defp toolbar_icon(%{name: "spaces"} = assigns) do
    ~H"""
    <svg class={icon_class(@active)} fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2V6zM14 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2V6zM4 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2v-2zM14 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2v-2z" />
    </svg>
    """
  end

  defp toolbar_icon(%{name: "people"} = assigns) do
    ~H"""
    <svg class={icon_class(@active)} fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z" />
    </svg>
    """
  end

  defp toolbar_icon(%{name: "settings"} = assigns) do
    ~H"""
    <svg class={icon_class(@active)} fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
    </svg>
    """
  end

  defp toolbar_icon(%{name: "graph"} = assigns) do
    ~H"""
    <svg class={icon_class(@active)} fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <circle cx="12" cy="5" r="2" stroke-width="1.5" />
      <circle cx="6" cy="17" r="2" stroke-width="1.5" />
      <circle cx="18" cy="17" r="2" stroke-width="1.5" />
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M12 7v5M8.5 15.5L11 12M15.5 15.5L13 12" />
    </svg>
    """
  end

  defp toolbar_icon(%{name: "back"} = assigns) do
    ~H"""
    <svg class={icon_class(@active)} fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 19l-7-7m0 0l7-7m-7 7h18" />
    </svg>
    """
  end

  defp toolbar_icon(%{name: "heart"} = assigns) do
    ~H"""
    <svg class={icon_class(@active)} fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4.318 6.318a4.5 4.5 0 000 6.364L12 20.364l7.682-7.682a4.5 4.5 0 00-6.364-6.364L12 7.636l-1.318-1.318a4.5 4.5 0 00-6.364 0z" />
    </svg>
    """
  end

  defp toolbar_icon(%{name: "reply"} = assigns) do
    ~H"""
    <svg class={icon_class(@active)} fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 10h10a8 8 0 018 8v2M3 10l6 6m-6-6l6-6" />
    </svg>
    """
  end

  defp toolbar_icon(%{name: "more"} = assigns) do
    ~H"""
    <svg class={icon_class(@active)} fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 12h.01M12 12h.01M19 12h.01M6 12a1 1 0 11-2 0 1 1 0 012 0zm7 0a1 1 0 11-2 0 1 1 0 012 0zm7 0a1 1 0 11-2 0 1 1 0 012 0z" />
    </svg>
    """
  end

  defp toolbar_icon(assigns) do
    ~H"""
    <svg class={icon_class(@active)} fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16M4 18h16" />
    </svg>
    """
  end

  # = ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  # SEARCH RESULTS COMPONENTS
  # ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

  defp result_section(assigns) do
    ~H"""
    <div class="space-y-2">
      <div class="flex items-center gap-2 px-2">
        <span class="text-[10px] font-bold text-white/30 uppercase tracking-[0.2em]">{@title}</span>
        <div class="h-px flex-1 bg-white/5"></div>
      </div>
      <div class="grid gap-1">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  defp action_result(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="omnibox_action"
      phx-value-action={@action.event}
      class="w-full flex items-center gap-3 p-2 rounded-2xl hover:bg-white/5 transition-all text-left group"
    >
      <div class="w-10 h-10 rounded-xl bg-amber-500/10 border border-amber-500/20 flex items-center justify-center shrink-0">
        <svg class="w-5 h-5 text-amber-500/80" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z" />
        </svg>
      </div>
      <div class="flex-1 min-w-0">
        <div class="text-sm font-medium text-white/90 group-hover:text-white leading-tight">{@action.label}</div>
        <div class="text-[10px] text-white/40 font-mono mt-0.5 tracking-tight group-hover:text-white/60 transition-colors">{@action.command}</div>
      </div>
      <svg class="w-4 h-4 text-white/10 group-hover:text-amber-500/40 transform group-hover:translate-x-0.5 transition-all" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
      </svg>
    </button>
    """
  end

  defp person_result(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="omnibox_select_person"
      phx-value-id={@person.id}
      class="w-full flex items-center gap-3 p-2 rounded-2xl hover:bg-white/5 transition-all text-left group"
    >
      <div
        class="w-10 h-10 rounded-full flex items-center justify-center text-xs font-bold border border-white/10 overflow-hidden shrink-0"
        style={"background-color: #{friend_color(@person)}"}
      >
        <%= if Map.get(@person, :avatar_url) do %>
          <img src={@person.avatar_url} class="w-full h-full object-cover" alt={@person.username} />
        <% else %>
          {String.first(@person.username) |> String.upcase()}
        <% end %>
      </div>
      <div class="flex-1 min-w-0">
        <div class="text-sm font-medium text-white/90 group-hover:text-white leading-tight truncate">
          @{@person.username}
        </div>
        <%= if @person.display_name do %>
          <div class="text-[10px] text-white/40 truncate mt-0.5 group-hover:text-white/60 transition-colors">{@person.display_name}</div>
        <% end %>
      </div>
      <svg class="w-4 h-4 text-white/10 group-hover:text-blue-500/40 transform group-hover:translate-x-0.5 transition-all" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
      </svg>
    </button>
    """
  end

  defp group_result(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="omnibox_select_group"
      phx-value-code={@group.code}
      class="w-full flex items-center gap-3 p-2 rounded-2xl hover:bg-white/5 transition-all text-left group"
    >
      <div class="w-10 h-10 rounded-xl bg-blue-500/10 border border-blue-500/20 flex items-center justify-center shrink-0">
        <svg class="w-5 h-5 text-blue-500/60" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z" />
        </svg>
      </div>
      <div class="flex-1 min-w-0">
        <div class="text-sm font-medium text-white/90 group-hover:text-white leading-tight truncate">
          {@group.name || @group.code}
        </div>
        <div class="text-[10px] text-white/40 truncate mt-0.5 group-hover:text-white/60 transition-colors">
          {length(Map.get(@group, :members, []))} members
        </div>
      </div>
      <svg class="w-4 h-4 text-white/10 group-hover:text-purple-500/40 transform group-hover:translate-x-0.5 transition-all" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
      </svg>
    </button>
    """
  end

  defp icon_class(active) do
    base = "w-6 h-6 transition-colors"
    if active, do: "#{base} text-white", else: "#{base} text-white/60"
  end
end
