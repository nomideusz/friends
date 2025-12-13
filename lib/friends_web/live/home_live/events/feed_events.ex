defmodule FriendsWeb.HomeLive.Events.FeedEvents do
  @moduledoc """
  Event handlers for Feed and Network filtering logic.
  Also handles pagination (load_more).
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
    |> update_dashboard_context()
    |> reset_feed()
  end

  def switch_feed(socket, mode) do
    socket
    |> assign(:feed_mode, mode)
    |> update_dashboard_context()
    |> reset_feed()
  end

  def set_network_filter(socket, filter) do
    socket
    |> assign(:network_filter, filter)
    |> update_dashboard_context()
    |> reset_feed()
  end

  def load_more(socket) do
    if socket.assigns.room_access_denied or socket.assigns.no_more_items do
      {:noreply, socket}
    else
      batch = @initial_batch
      offset = socket.assigns.item_count || 0

      {items, no_more?} = fetch_items(socket, batch, offset)

      # Update state
      new_count = offset + length(items)
      new_photo_order = merge_photo_order(socket.assigns.photo_order, photo_ids(items), :back)

      socket =
        socket
        |> assign(:item_count, new_count)
        |> assign(:no_more_items, no_more?)
        |> assign(:photo_order, new_photo_order)

      # Stream items (append)
      socket =
        Enum.reduce(items, socket, fn item, acc ->
          stream_insert(acc, :items, item)
        end)

      {:noreply, socket}
    end
  end

  # --- Private Helpers ---

  defp reset_feed(socket) do
    {items, no_more?} = fetch_items(socket, @initial_batch, 0)
    error = if items == [] and socket.assigns.feed_mode == "friends" and is_nil(socket.assigns.current_user) and socket.assigns.network_filter != "all", do: "register to see your network", else: nil

    socket =
      socket
      |> assign(:item_count, length(items))
      |> assign(:no_more_items, no_more?)
      |> assign(:photo_order, photo_ids(items))
      |> stream(:items, items, reset: true, dom_id: &"item-#{&1.unique_id}")

    if error do
      {:noreply, put_flash(socket, :error, error)}
    else
      {:noreply, socket}
    end
  end

  defp update_dashboard_context(socket) do
    if socket.assigns.feed_mode == "friends" and socket.assigns.current_user do
      current_user_id = socket.assigns.current_user.id
      socket
      |> assign(:trusted_friends, Social.list_trusted_friends(current_user_id))
      |> assign(:outgoing_trust_requests, Social.list_sent_trust_requests(current_user_id))
    else
      socket
    end
  end

  defp fetch_items(socket, batch, offset) do
    mode = socket.assigns.feed_mode
    current_user = socket.assigns.current_user

    case mode do
      "room" ->
        room = socket.assigns.room
        photos = Social.list_photos(room.id, batch, offset: offset)
        notes = Social.list_notes(room.id, batch, offset: offset)
        items = build_items(photos, notes)
        {items, length(items) < batch}

      "friends" ->
        filter = socket.assigns.network_filter

        cond do
          filter == "all" ->
            photos = Social.list_public_photos(batch, offset: offset)
            notes = Social.list_public_notes(batch, offset: offset)
            items = build_items(photos, notes)
            {items, length(items) < batch}

          is_nil(current_user) ->
            {[], true}

          true ->
            {photos, notes} =
              case filter do
                "me" ->
                  {Social.list_user_photos(current_user.id, batch, offset: offset),
                   Social.list_user_notes(current_user.id, batch, offset: offset)}

                _ ->
                  {Social.list_friends_photos(current_user.id, batch, offset: offset),
                   Social.list_friends_notes(current_user.id, batch, offset: offset)}
              end

            items = build_items(photos, notes)
            {items, length(items) < batch}
        end
    end
  end
end
