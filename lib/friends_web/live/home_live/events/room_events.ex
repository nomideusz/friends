defmodule FriendsWeb.HomeLive.Events.RoomEvents do
  @moduledoc """
  Event handlers for Room/Group management and Member interactions.
  """
  import Phoenix.Component
  import Phoenix.LiveView
  import FriendsWeb.HomeLive.Helpers
  alias Friends.Social
  use FriendsWeb, :verified_routes

  # --- Room Modal Handlers ---

  def open_room_modal(socket) do
    {:noreply, assign(socket, :show_room_modal, true)}
  end

  def close_room_modal(socket) do
    {:noreply, assign(socket, :show_room_modal, false)}
  end

  def update_join_code(socket, code) do
    {:noreply, assign(socket, :join_code, code)}
  end

  def join_room(socket, code) do
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

  def go_to_public_square(socket) do
    {:noreply,
     socket
     |> assign(:show_room_modal, false)
     |> push_navigate(to: ~p"/r/lobby")}
  end

  # --- Create Group Handlers ---

  def open_create_group_modal(socket) do
    if socket.assigns.current_user do
      {:noreply, socket |> assign(:create_group_modal, true) |> assign(:new_room_name, "")}
    else
      {:noreply, put_flash(socket, :error, "please login to create groups")}
    end
  end

  def close_create_group_modal(socket) do
    {:noreply, socket |> assign(:create_group_modal, false) |> assign(:new_room_name, "")}
  end

  def update_room_form(socket, params) do
    name = params["name"] || ""
    is_private = params["is_private"] == "on"

    {:noreply,
     socket
     |> assign(:new_room_name, name)
     |> assign(:create_private_room, is_private)}
  end

  def create_room(socket, params) do
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
            Social.create_private_room(
              %{code: code, name: name, created_by: socket.assigns.user_id},
              user.id
            )
        end
      else
        # Correctly calling create_room for public room
        Social.create_room(%{code: code, name: name, created_by: socket.assigns.user_id})
      end

    case result do
      {:ok, _room} ->
        {:noreply,
         socket
         |> assign(:show_room_modal, false)
         |> assign(:new_room_name, "")
         |> assign(:create_private_room, false)
         |> assign(:show_contact_sheet, true)
         |> assign(:contact_mode, :invite_members)
         |> push_navigate(to: ~p"/r/#{code}")}

      {:error, :not_registered} ->
        {:noreply, put_flash(socket, :error, "register to create private rooms")}

      {:error, :not_implemented} ->
        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "failed to create")}
    end
  end

  # Special handler for the "create_group" simplified form
  def create_group(socket, name) do
    name = String.trim(name)

    case socket.assigns.current_user do
      nil ->
        {:noreply, put_flash(socket, :error, "please login to create groups")}

      user ->
        code = Social.generate_room_code()
        group_name = if name == "", do: nil, else: name

        case Social.create_private_room(
               %{code: code, name: group_name, created_by: socket.assigns.user_id},
               user.id
             ) do
          {:ok, _room} ->
            # Navigate to the new room and open the invite sheet
            {:noreply,
             socket
             |> assign(:create_group_modal, false)
             |> assign(:new_room_name, "")
             |> assign(:show_contact_sheet, true)
             |> assign(:contact_mode, :invite_members)
             |> push_navigate(to: ~p"/r/#{code}")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "failed to create group")}
        end
    end
  end

  def switch_room(socket, code) do
    {:noreply,
     socket
     |> assign(:show_room_modal, false)
     |> push_navigate(to: ~p"/r/#{code}")}
  end

  # --- Member Logic ---

  def add_room_member(socket, username) do
    do_add_room_member(socket, username)
  end

  def add_room_member_by_username(socket, %{"query" => username}) do
    if username && String.trim(username) != "" do
      do_add_room_member(socket, username)
    else
      {:noreply, put_flash(socket, :error, "please enter a username")}
    end
  end

  defp do_add_room_member(socket, username) do
    room = socket.assigns.room
    owner_id = socket.assigns.current_user && socket.assigns.current_user.id
    username = String.trim(username)

    cond do
      is_nil(owner_id) ->
        {:noreply, put_flash(socket, :error, "login to invite")}

      room.owner_id != owner_id or not room.is_private ->
        {:noreply, put_flash(socket, :error, "only owners can invite to private groups")}

      true ->
        user = Social.get_user_by_username(username)

        cond do
          is_nil(user) ->
            {:noreply, put_flash(socket, :error, "user not found")}

          Social.can_access_room?(room, user.id) ->
            {:noreply, put_flash(socket, :info, "@#{user.username} is already a member")}

          true ->
            # Default role "member"
            case Social.add_room_member(room.id, user.id, "member", owner_id) do
              {:ok, _member} ->
                # Update friends list logic removed as it was unused and caused warnings


                {:noreply,
                 socket
                 |> put_flash(:info, "@#{user.username} added to group")
                 |> assign(:invite_username, "") # Clear input
                 |> assign(:room_invite_username, "") # Clear input (legacy)
                 |> assign(:member_invite_search, "")}

              {:error, _} ->
                {:noreply, put_flash(socket, :error, "failed to add user")}
            end
        end
    end
  end

  def remove_room_member(socket, user_id_str) do
    case safe_to_integer(user_id_str) do
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "invalid user")}

      {:ok, user_id} ->
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
  end

  def search_member_invite(socket, %{"query" => query}) do
    query = String.trim(query)
    
    # We update the search query. Filtering happens in the component for now 
    # (or in a future real-time update if we had a separate filtered_friends assign).
    # Since we don't want to lose the original friends list in :friends, we just
    # pass the query down.
    
    {:noreply, 
      socket 
      |> assign(:member_invite_search, query)
      |> assign(:invite_username, query)
    } 
  end

  def update_room_invite_username(socket, username) do
    {:noreply, assign(socket, :room_invite_username, username)}
  end

  def invite_to_room(socket, user_id_str) do
    case safe_to_integer(user_id_str) do
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "invalid user")}

      {:ok, user_id} ->
        room = socket.assigns.room
        current_user = socket.assigns.current_user

        case current_user do
          nil ->
            {:noreply, put_flash(socket, :error, "register first")}

          _ ->
            case Social.invite_to_room(room.id, current_user.id, user_id) do
              {:ok, _member} ->
                # Refresh room members is separate?
                # Original code (2441) calls Social.list_room_members?
                # Let's include refresh.
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
  end

  def create_invite(socket) do
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

  def open_dm(socket, friend_user_id) do
    user = socket.assigns.current_user

    if user do
      {friend_id, _} = Integer.parse(friend_user_id)
      # Ensure DM room exists or create it
      case Social.get_or_create_dm_room(user.id, friend_id) do
        {:ok, room} ->
          {:noreply, push_navigate(socket, to: ~p"/r/#{room.code}")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not open chat")}
      end
    else
      {:noreply, put_flash(socket, :error, "Please log in")}
    end
  end

  # --- PIN / UNPIN CONTENT ---

  def pin_item(socket, item_type, item_id_str) do
    case {socket.assigns.current_user, safe_to_integer(item_id_str)} do
      {nil, _} ->
        {:noreply, put_flash(socket, :error, "Please log in")}

      {_, {:error, _}} ->
        {:noreply, put_flash(socket, :error, "Invalid item")}

      {user, {:ok, item_id}} ->
        room = socket.assigns.room

        # Only owner/admins can pin
        if can_manage_room?(room, user) do
          result = case item_type do
            "photo" -> Social.pin_photo(item_id, room.code)
            "note" -> Social.pin_note(item_id, room.code)
            _ -> {:error, :unknown_type}
          end

          case result do
            {:ok, updated_item} ->
              # Update stream with the new pinned_at value
              item_with_type =
                updated_item
                |> Map.from_struct()
                |> Map.put(:type, String.to_existing_atom(item_type))
                |> Map.put(:unique_id, "#{item_type}-#{item_id}")

              {:noreply, 
               socket
               |> stream_insert(:items, item_with_type)
               |> put_flash(:info, "Pinned!")}
            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Could not pin")}
          end
        else
          {:noreply, put_flash(socket, :error, "Only admins can pin content")}
        end
    end
  end

  def unpin_item(socket, item_type, item_id_str) do
    case {socket.assigns.current_user, safe_to_integer(item_id_str)} do
      {nil, _} ->
        {:noreply, put_flash(socket, :error, "Please log in")}

      {_, {:error, _}} ->
        {:noreply, put_flash(socket, :error, "Invalid item")}

      {user, {:ok, item_id}} ->
        room = socket.assigns.room

        if can_manage_room?(room, user) do
          result = case item_type do
            "photo" -> Social.unpin_photo(item_id, room.code)
            "note" -> Social.unpin_note(item_id, room.code)
            _ -> {:error, :unknown_type}
          end

          case result do
            {:ok, updated_item} ->
              # Update stream with the cleared pinned_at value
              item_with_type =
                updated_item
                |> Map.from_struct()
                |> Map.put(:type, String.to_existing_atom(item_type))
                |> Map.put(:unique_id, "#{item_type}-#{item_id}")

              {:noreply, 
               socket
               |> stream_insert(:items, item_with_type)
               |> put_flash(:info, "Unpinned")}
            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Could not unpin")}
          end
        else
          {:noreply, put_flash(socket, :error, "Only admins can unpin content")}
        end
    end
  end

  # Check if user is owner or admin of the room
  defp can_manage_room?(room, user) do
    if room.owner_id == user.id do
      true
    else
      case Social.get_room_member(room.id, user.id) do
        nil -> false
        member -> member.role in ["admin", "owner"]
      end
    end
  end
end
