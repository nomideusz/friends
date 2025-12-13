defmodule FriendsWeb.HomeLive.Events.FeedEvents do
  @moduledoc """
  Event handlers for Feed and Network filtering logic.
  """
  import Phoenix.Component
  import Phoenix.LiveView
  import FriendsWeb.HomeLive.Helpers
  alias Friends.Social

  @initial_batch 20

  def toggle_contacts(socket) do
    {:noreply, assign(socket, :contacts_collapsed, !socket.assigns.contacts_collapsed)}
  end

  def toggle_groups(socket) do
    {:noreply, assign(socket, :groups_collapsed, !socket.assigns.groups_collapsed)}
  end

  def set_feed_view(socket, view) do
    {new_mode, new_filter} =
      case view do
        "room" -> {"room", socket.assigns.network_filter}
        "friends" -> {"friends", "trusted"}
        "public" -> {"friends", "all"}
        "me" -> {"friends", "me"}
      end

    socket
    |> assign(:feed_mode, new_mode)
    |> assign(:network_filter, new_filter)
    |> fetch_feed_content()
    |> reply_socket()
  end

  def switch_feed(socket, mode) do
    socket
    |> assign(:feed_mode, mode)
    |> fetch_feed_content()
    |> reply_socket()
  end

  def set_network_filter(socket, filter) do
    socket
    |> assign(:network_filter, filter)
    |> fetch_feed_content()
    |> reply_socket()
  end

  defp reply_socket(socket), do: {:noreply, socket}

  defp fetch_feed_content(socket) do
    mode = socket.assigns.feed_mode
    current_user = socket.assigns.current_user

    case mode do
      "room" ->
        # Fetches content for current room
        room = socket.assigns.room
        photos = Social.list_photos(room.id, @initial_batch, offset: 0)
        notes = Social.list_notes(room.id, @initial_batch, offset: 0)
        items = build_items(photos, notes)

        assign_items(socket, items)

      "friends" ->
        # Fetches content for network/friends/public
        # Update network lists if user logged in
        socket =
          if current_user do
            socket
            |> assign(:trusted_friends, Social.list_trusted_friends(current_user.id))
            |> assign(:outgoing_trust_requests, Social.list_sent_trust_requests(current_user.id))
          else
            socket
          end

        # If user is nil, we can only show content if filter is "all" (public)
        # But logically, if filter is "trusted" (default), we show error?
        # Standardizing: If nil and NOT "all", show error.
        # But simple approach: Just try fetching.

        filter = socket.assigns.network_filter

        {items, error} =
          cond do
            filter == "all" ->
              # Public content - allowed for everyone
              photos = Social.list_public_photos(@initial_batch, offset: 0)
              notes = Social.list_public_notes(@initial_batch, offset: 0)
              {build_items(photos, notes), nil}

            is_nil(current_user) ->
              # Not public, and no user -> Error
              {[], "register to see your network"}

            true ->
              # Logged in user, specific filter
              {photos, notes} =
                case filter do
                  "me" ->
                    {Social.list_user_photos(current_user.id, @initial_batch, offset: 0),
                     Social.list_user_notes(current_user.id, @initial_batch, offset: 0)}

                  # "trusted" or other
                  _ ->
                    {Social.list_friends_photos(current_user.id, @initial_batch, offset: 0),
                     Social.list_friends_notes(current_user.id, @initial_batch, offset: 0)}
                end

              {build_items(photos, notes), nil}
          end

        socket = assign_items(socket, items)

        if error do
          put_flash(socket, :error, error)
        else
          socket
        end
    end
  end

  defp assign_items(socket, items) do
    no_more = length(items) < @initial_batch

    socket
    |> assign(:item_count, length(items))
    |> assign(:no_more_items, no_more)
    |> assign(:photo_order, photo_ids(items))
    # Reset needed for mode switches
    |> stream(:items, items, reset: true, dom_id: &"item-#{&1.unique_id}")
  end
end
