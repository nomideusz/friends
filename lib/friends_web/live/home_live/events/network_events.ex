defmodule FriendsWeb.HomeLive.Events.NetworkEvents do
  @moduledoc """
  Event handlers for Network (Friends/Trust) management.
  """
  import Phoenix.Component
  import Phoenix.LiveView
  import FriendsWeb.HomeLive.Helpers
  alias Friends.Social
  use FriendsWeb, :verified_routes

  # --- Network Modal ---

  def open_network_modal(socket) do
    {:noreply,
     socket
     |> assign(:show_network_modal, true)
     |> assign(:network_tab, "friends")}
  end

  def close_network_modal(socket) do
    {:noreply,
     socket
     |> assign(:show_network_modal, false)
     |> assign(:network_tab, "friends")
     |> assign(:friend_search, "")
     |> assign(:friend_search_results, [])}
  end

  def switch_network_tab(socket, tab) do
    {:noreply, assign(socket, :network_tab, tab)}
  end

  # --- People Sheet (New) ---

  def open_contacts_sheet(socket, mode \\ :add_contact) do
    mode_atom = if is_binary(mode), do: String.to_existing_atom(mode), else: mode
    
    # Subscribe to user-specific updates for live changes
    if socket.assigns.current_user do
      Phoenix.PubSub.subscribe(Friends.PubSub, "friends:user:#{socket.assigns.current_user.id}")
    end
    
    {:noreply,
     socket
     |> assign(:show_avatar_menu, false)
     |> assign(:show_people_modal, true)
     |> assign(:contact_mode, mode_atom)
     |> assign(:contact_sheet_search, "")
     |> assign(:contact_search_results, [])}
  end

  def close_people_modal(socket) do
    # Unsubscribe from user-specific updates
    if socket.assigns.current_user do
      Phoenix.PubSub.unsubscribe(Friends.PubSub, "friends:user:#{socket.assigns.current_user.id}")
    end
    
    {:noreply,
     socket
     |> assign(:show_people_modal, false)
     |> assign(:contact_sheet_search, "")
     |> assign(:contact_search_results, [])}
  end

  def contact_search(socket, query) do
    query = String.trim(query)
    current_user_id = socket.assigns.current_user && socket.assigns.current_user.id
    
    results =
      if String.length(query) >= 2 do
        # Exclude self and current friends from "add" results? 
        # Actually proper search should return everyone but status differs.
        Social.search_users(query, current_user_id)
      else
        []
      end

    {:noreply,
     socket
     |> assign(:contact_sheet_search, query)
     |> assign(:contact_search_results, results)}
  end

  def send_friend_request(socket, user_id_str) do
    case safe_to_integer(user_id_str) do
      {:ok, user_id} ->
        case Social.add_friend(socket.assigns.current_user.id, user_id) do
          {:ok, _} ->
             # Broadcast to target user for live update
             Phoenix.PubSub.broadcast(Friends.PubSub, "friends:user:#{user_id}", {:connection_request_received, socket.assigns.current_user.id})
             
             # Refresh all relevant lists - auto-accept might have happened
             friends = Social.list_friends(socket.assigns.current_user.id)
             pending = Social.list_friend_requests(socket.assigns.current_user.id)
             sent = Social.list_sent_friend_requests(socket.assigns.current_user.id)
             
             {:noreply, 
              socket 
              |> assign(:friends, friends)
              |> assign(:pending_requests, pending)
              |> assign(:outgoing_friend_requests, sent)
              |> put_flash(:info, "Connection request sent!")}
          {:error, _} -> {:noreply, put_flash(socket, :error, "Could not send request")}
        end
      _ -> {:noreply, socket}
    end
  end

  def accept_friend_request(socket, user_id_str) do
    case safe_to_integer(user_id_str) do
      {:ok, user_id} ->
        case Social.accept_friend(socket.assigns.current_user.id, user_id) do
          {:ok, _} ->
             # Broadcast to requester for live update
             Phoenix.PubSub.broadcast(Friends.PubSub, "friends:user:#{user_id}", {:connection_accepted, socket.assigns.current_user.id})
             # Refresh friends and requests
             friends = Social.list_friends(socket.assigns.current_user.id)
             requests = Social.list_friend_requests(socket.assigns.current_user.id)
             {:noreply, 
              socket 
              |> assign(:friends, friends)
              |> assign(:pending_requests, requests)
              |> put_flash(:info, "Connected!")}
          {:error, _} -> {:noreply, put_flash(socket, :error, "Could not accept")}
        end
      _ -> {:noreply, socket}
    end
  end

  def decline_friend_request(socket, user_id_str) do
    # Logic to decline (remove request)
    # Social.remove_friend works for pending request too?
    # Relationships.remove_friend checks get_friendship which returns pending/accepted.
    # So yes, remove_friend works.
    case safe_to_integer(user_id_str) do
      {:ok, user_id} ->
        Social.remove_friend(socket.assigns.current_user.id, user_id)
        requests = Social.list_friend_requests(socket.assigns.current_user.id)
        {:noreply, assign(socket, :pending_requests, requests)}
      _ -> {:noreply, socket}
    end
  end

  def cancel_request(socket, user_id_str) do
    # Cancel SENT friend request
    case safe_to_integer(user_id_str) do
      {:ok, user_id} ->
        Social.remove_friend(socket.assigns.current_user.id, user_id)
        sent = Social.list_sent_friend_requests(socket.assigns.current_user.id)
        {:noreply, assign(socket, :outgoing_friend_requests, sent)}
      _ -> {:noreply, socket}
    end
  end

  def remove_contact(socket, user_id_str) do
    case safe_to_integer(user_id_str) do
      {:ok, user_id} ->
        Social.remove_friend(socket.assigns.current_user.id, user_id)
        friends = Social.list_friends(socket.assigns.current_user.id)
        {:noreply, 
         socket 
         |> assign(:friends, friends)
         |> put_flash(:info, "Removed from your people")}
      _ -> {:noreply, socket}
    end
  end

  def remove_trusted_friend(socket, user_id_str) do
    case safe_to_integer(user_id_str) do
      {:ok, user_id} ->
        Social.remove_trusted_friend(socket.assigns.current_user.id, user_id)
        # Refresh
        trusted = Social.list_trusted_friends(socket.assigns.current_user.id)
        trusted_ids = Enum.map(trusted, & &1.trusted_user_id)
        
        {:noreply,
         socket
         |> assign(:trusted_friends, trusted)
         |> assign(:trusted_friend_ids, trusted_ids)
         |> put_flash(:info, "Removed from recovery contacts")}
      _ -> {:noreply, socket}
    end
  end

  def decline_trusted_friend(socket, user_id_str) do
     case safe_to_integer(user_id_str) do
      {:ok, user_id} ->
        Social.decline_trust_request(socket.assigns.current_user.id, user_id) # user is requester
        incoming = Social.list_pending_trust_requests(socket.assigns.current_user.id)
        {:noreply, assign(socket, :incoming_requests, incoming)}
      _ -> {:noreply, socket}
    end
  end

  # --- Friend Search ---

  def search_friends(socket, query) do
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

  # --- Trust Management ---

  def add_trusted_friend(socket, user_id_str) do
    case safe_to_integer(user_id_str) do
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "invalid user")}

      {:ok, user_id} ->
        case socket.assigns.current_user do
          nil ->
            {:noreply, put_flash(socket, :error, "register first")}

          current_user ->
            case Social.add_trusted_friend(current_user.id, user_id) do
              {:ok, _tf} ->
                # Broadcast to target user for live update
                Phoenix.PubSub.broadcast(Friends.PubSub, "friends:user:#{user_id}", {:trust_request_received, current_user.id})
                outgoing = Social.list_sent_trust_requests(current_user.id)

                {:noreply,
                 socket
                 |> assign(:friend_search, "")
                 |> assign(:friend_search_results, [])
                 |> assign(:outgoing_trust_requests, outgoing)
                 |> put_flash(:info, "Recovery invite sent")}

              {:error, :cannot_trust_self} ->
                {:noreply, put_flash(socket, :error, "can't trust yourself")}

              {:error, :max_trusted_friends} ->
                {:noreply, put_flash(socket, :error, "Max 5 recovery contacts")}

              {:error, _} ->
                {:noreply, put_flash(socket, :error, "already requested")}
            end
        end
    end
  end

  def confirm_trust(socket, user_id_str) do
    case safe_to_integer(user_id_str) do
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "invalid user")}

      {:ok, user_id} ->
        case socket.assigns.current_user do
          nil ->
            {:noreply, put_flash(socket, :error, "register first")}

          current_user ->
            case Social.confirm_trusted_friend(current_user.id, user_id) do
              {:ok, _} ->
                # Broadcast to requester for live update
                Phoenix.PubSub.broadcast(Friends.PubSub, "friends:user:#{user_id}", {:trust_confirmed, current_user.id})
                # Refresh the pending requests and trusted friends list
                pending = Social.list_pending_trust_requests(current_user.id)
                trusted = Social.list_trusted_friends(current_user.id)
                trusted_ids = Enum.map(trusted, & &1.trusted_user_id)

                {:noreply,
                 socket
                 |> assign(:incoming_trust_requests, pending)
                 |> assign(:trusted_friends, trusted)
                 |> assign(:trusted_friend_ids, trusted_ids)
                 |> put_flash(:info, "Recovery contact confirmed")}

              {:error, _} ->
                {:noreply, put_flash(socket, :error, "failed")}
            end
        end
    end
  end

  # --- Recovery Voting ---

  def vote_recovery(socket, %{"user_id" => user_id_str, "vote" => vote}) do
    case safe_to_integer(user_id_str) do
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "invalid user")}

      {:ok, user_id} ->
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
                  {:noreply, put_flash(socket, :error, "Not a recovery contact")}

                {:error, _} ->
                  {:noreply, put_flash(socket, :error, "already voted")}
              end
            end
        end
    end
  end

  # --- Direct Message (1-1 Chat) ---
  
  def open_dm(socket, user_id_str) do
    case safe_to_integer(user_id_str) do
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Invalid user")}

      {:ok, target_user_id} ->
        case socket.assigns.current_user do
          nil ->
            {:noreply, put_flash(socket, :error, "Please register first")}

          current_user ->
            # Get or create a DM room between current user and target user
            alias Friends.Social.Rooms
            
            case Rooms.get_or_create_dm_room(current_user.id, target_user_id) do
              {:ok, room} ->
                # Close the contacts sheet and navigate to the room
                socket =
                  socket
                  |> assign(:show_people_modal, false)
                  |> push_navigate(to: "/r/#{room.code}")
                  
                {:noreply, socket}

              {:error, _reason} ->
                {:noreply, put_flash(socket, :error, "Could not open chat")}
            end
        end
    end
  end
end
