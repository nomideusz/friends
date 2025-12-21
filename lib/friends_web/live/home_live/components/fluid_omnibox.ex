defmodule FriendsWeb.HomeLive.Components.FluidOmnibox do
  @moduledoc """
  Unified omnibox search component.
  Supports:
  - @username -> People search
  - #group -> Group search
  - /command -> Quick actions
  - Plain text -> Content search
  """
  use FriendsWeb, :html
  import FriendsWeb.HomeLive.Helpers

  # ============================================================================
  # OMNIBOX MODAL
  # Full-screen search overlay with grouped results
  # ============================================================================

  attr :show, :boolean, default: false
  attr :query, :string, default: ""
  attr :results, :map, default: %{people: [], groups: [], actions: []}
  attr :current_user, :map, required: true

  def omnibox(assigns) do
    ~H"""
    <%= if @show do %>
      <div
        id="omnibox-overlay"
        class="fixed inset-0 z-[250] bg-black/90 backdrop-blur-xl animate-in fade-in duration-150"
        phx-window-keydown="close_omnibox"
        phx-key="escape"
      >
        <div class="flex flex-col h-full max-w-2xl mx-auto p-4 pt-safe">
          <%!-- Search Input --%>
          <div class="relative mb-4">
            <div class="absolute left-4 top-1/2 -translate-y-1/2 text-white/40">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
              </svg>
            </div>
            <input
              type="text"
              id="omnibox-input"
              name="query"
              value={@query}
              phx-keyup="omnibox_search"
              phx-debounce="150"
              placeholder="Search people, groups, or type / for commands..."
              autocomplete="off"
              autofocus
              class="w-full pl-12 pr-12 py-4 bg-white/5 border border-white/10 rounded-2xl text-white text-lg placeholder:text-white/30 focus:outline-none focus:border-white/30 focus:ring-1 focus:ring-white/20"
            />
            <button
              type="button"
              phx-click="close_omnibox"
              class="absolute right-3 top-1/2 -translate-y-1/2 p-2 text-white/40 hover:text-white/70 transition-colors cursor-pointer"
            >
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>

          <%!-- Results --%>
          <div class="flex-1 overflow-y-auto custom-scrollbar space-y-6">
            <%!-- Quick Actions (when query starts with /) --%>
            <%= if String.starts_with?(@query, "/") do %>
              <.result_section title="Quick Actions" icon="zap">
                <.action_item label="Create Group" command="/new group" event="open_create_group_modal" />
                <.action_item label="Invite Friend" command="/invite" event="open_contacts_sheet" />
                <.action_item label="Settings" command="/settings" event="open_profile_sheet" />
                <.action_item label="Network Graph" command="/graph" event="show_fullscreen_graph" />
              </.result_section>
            <% end %>

            <%!-- People Results --%>
            <%= if length(@results.people) > 0 do %>
              <.result_section title="People" icon="user">
                <%= for person <- @results.people do %>
                  <.person_result person={person} />
                <% end %>
              </.result_section>
            <% end %>

            <%!-- Groups Results --%>
            <%= if length(@results.groups) > 0 do %>
              <.result_section title="Groups" icon="users">
                <%= for group <- @results.groups do %>
                  <.group_result group={group} />
                <% end %>
              </.result_section>
            <% end %>

            <%!-- Empty State --%>
            <%= if @query != "" and not String.starts_with?(@query, "/") and length(@results.people) == 0 and length(@results.groups) == 0 do %>
              <div class="text-center py-12 text-white/40">
                <svg class="w-12 h-12 mx-auto mb-3 opacity-50" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
                </svg>
                <p class="text-sm">No results for "<%= @query %>"</p>
                <p class="text-xs mt-1 text-white/30">Try @username for people or #group for groups</p>
              </div>
            <% end %>

            <%!-- Hint when empty --%>
            <%= if @query == "" do %>
              <div class="text-center py-12 text-white/30">
                <div class="space-y-4">
                  <div class="flex items-center justify-center gap-2">
                    <span class="px-2 py-1 bg-white/5 rounded text-xs font-mono">@</span>
                    <span class="text-sm">Search people</span>
                  </div>
                  <div class="flex items-center justify-center gap-2">
                    <span class="px-2 py-1 bg-white/5 rounded text-xs font-mono">#</span>
                    <span class="text-sm">Search groups</span>
                  </div>
                  <div class="flex items-center justify-center gap-2">
                    <span class="px-2 py-1 bg-white/5 rounded text-xs font-mono">/</span>
                    <span class="text-sm">Quick actions</span>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  # ============================================================================
  # RESULT SECTION
  # ============================================================================

  attr :title, :string, required: true
  attr :icon, :string, required: true
  slot :inner_block, required: true

  defp result_section(assigns) do
    ~H"""
    <div>
      <div class="flex items-center gap-2 mb-2 px-2">
        <span class="text-xs font-medium text-white/40 uppercase tracking-wider">{@title}</span>
      </div>
      <div class="space-y-1">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  # ============================================================================
  # PERSON RESULT
  # ============================================================================

  attr :person, :map, required: true

  defp person_result(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="omnibox_select_person"
      phx-value-id={@person.id}
      class="w-full flex items-center gap-3 p-3 rounded-xl bg-white/5 hover:bg-white/10 transition-colors cursor-pointer group text-left"
    >
      <div
        class="w-10 h-10 rounded-full flex items-center justify-center text-sm font-bold border border-white/10 overflow-hidden"
        style={"background-color: #{friend_color(@person)}"}
      >
        <%= if Map.get(@person, :avatar_url) do %>
          <img src={@person.avatar_url} class="w-full h-full object-cover" alt={@person.username} />
        <% else %>
          {String.first(@person.username) |> String.upcase()}
        <% end %>
      </div>
      <div class="flex-1 min-w-0">
        <div class="font-medium text-white group-hover:text-white truncate">
          @{@person.username}
        </div>
        <%= if @person.display_name do %>
          <div class="text-xs text-white/40 truncate">{@person.display_name}</div>
        <% end %>
      </div>
      <svg class="w-5 h-5 text-white/20 group-hover:text-white/40" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
      </svg>
    </button>
    """
  end

  # ============================================================================
  # GROUP RESULT
  # ============================================================================

  attr :group, :map, required: true

  defp group_result(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="omnibox_select_group"
      phx-value-code={@group.code}
      class="w-full flex items-center gap-3 p-3 rounded-xl bg-white/5 hover:bg-white/10 transition-colors cursor-pointer group text-left"
    >
      <div class="w-10 h-10 rounded-xl bg-gradient-to-br from-blue-500/20 to-purple-500/20 border border-white/10 flex items-center justify-center">
        <svg class="w-5 h-5 text-white/60" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z" />
        </svg>
      </div>
      <div class="flex-1 min-w-0">
        <div class="font-medium text-white group-hover:text-white truncate">
          {@group.name || @group.code}
        </div>
        <div class="text-xs text-white/40">
          {length(Map.get(@group, :members, []))} members
        </div>
      </div>
      <svg class="w-5 h-5 text-white/20 group-hover:text-white/40" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
      </svg>
    </button>
    """
  end

  # ============================================================================
  # ACTION ITEM
  # ============================================================================

  attr :label, :string, required: true
  attr :command, :string, required: true
  attr :event, :string, required: true

  defp action_item(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="omnibox_action"
      phx-value-action={@event}
      class="w-full flex items-center gap-3 p-3 rounded-xl bg-white/5 hover:bg-white/10 transition-colors cursor-pointer group text-left"
    >
      <div class="w-10 h-10 rounded-xl bg-gradient-to-br from-amber-500/20 to-orange-500/20 border border-white/10 flex items-center justify-center">
        <svg class="w-5 h-5 text-amber-400/80" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z" />
        </svg>
      </div>
      <div class="flex-1 min-w-0">
        <div class="font-medium text-white group-hover:text-white">{@label}</div>
        <div class="text-xs text-white/40 font-mono">{@command}</div>
      </div>
      <svg class="w-5 h-5 text-white/20 group-hover:text-white/40" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
      </svg>
    </button>
    """
  end
end
