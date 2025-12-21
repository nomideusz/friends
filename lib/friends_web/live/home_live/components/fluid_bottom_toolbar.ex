defmodule FriendsWeb.HomeLive.Components.FluidBottomToolbar do
  @moduledoc """
  Unified bottom toolbar that adapts based on context.
  Replaces corner orb navigation with a consistent spatial interaction model.
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

  def bottom_toolbar(assigns) do
    ~H"""
    <div class="fixed bottom-0 inset-x-0 z-[100] pointer-events-none pb-safe">
      <div class="flex justify-center px-4 pb-4">
        <nav class="pointer-events-auto flex items-center gap-1 px-2 py-2 bg-neutral-900/90 backdrop-blur-xl border border-white/10 rounded-2xl shadow-2xl">
          <%= case @context do %>
            <% :feed -> %>
              <.toolbar_button icon="search" label="Search" event="open_omnibox" />
              <.toolbar_button icon="plus" label="Create" event="open_create_menu" />
              <.toolbar_button icon="chat" label="Chats" event="open_groups_sheet" badge={@unread_count} />
              <.toolbar_avatar current_user={@current_user} event="open_profile_sheet" />
            <% :room -> %>
              <.toolbar_button icon="plus" label="Add" event="toggle_add_menu" />
              <.toolbar_button icon="chat" label="Chat" event="toggle_chat_visibility" active={@show_chat} />
              <.toolbar_button icon="people" label="People" event="open_contacts_sheet" />
              <.toolbar_button icon="settings" label="Room" event="open_room_settings" />
            <% :focused -> %>
              <.toolbar_button icon="back" label="Back" event="close_focused_view" />
              <.toolbar_button icon="heart" label="React" event="react_to_item" />
              <.toolbar_button icon="reply" label="Reply" event="reply_to_item" />
              <.toolbar_button icon="more" label="More" event="show_item_actions" />
            <% _ -> %>
              <%!-- Fallback to feed --%>
              <.toolbar_button icon="search" label="Search" event="open_omnibox" />
              <.toolbar_button icon="plus" label="Create" event="open_create_menu" />
              <.toolbar_button icon="chat" label="Chats" event="open_groups_sheet" />
              <.toolbar_avatar current_user={@current_user} event="open_profile_sheet" />
          <% end %>
        </nav>
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
  # TOOLBAR AVATAR
  # ============================================================================

  attr :current_user, :map, required: true
  attr :event, :string, required: true

  defp toolbar_avatar(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={@event}
      class="relative flex flex-col items-center justify-center w-16 h-14 rounded-xl hover:bg-white/5 transition-all cursor-pointer"
    >
      <div
        class="w-8 h-8 rounded-full flex items-center justify-center text-xs font-bold text-black border-2 border-white/20 overflow-hidden"
        style={"background-color: #{friend_color(@current_user)}"}
      >
        <%= if Map.get(@current_user, :avatar_url) do %>
          <img src={@current_user.avatar_url} class="w-full h-full object-cover" alt="You" />
        <% else %>
          {String.first(@current_user.username) |> String.upcase()}
        <% end %>
      </div>
      <span class="text-[10px] mt-1 font-medium text-white/50">You</span>
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
    # Fallback icon
    ~H"""
    <svg class={icon_class(@active)} fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16M4 18h16" />
    </svg>
    """
  end

  defp icon_class(active) do
    base = "w-6 h-6 transition-colors"
    if active, do: "#{base} text-white", else: "#{base} text-white/60"
  end
end
