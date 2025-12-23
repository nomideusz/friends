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
     |> assign(:show_contact_sheet, true)
     |> assign(:contact_mode, mode_atom)
     |> assign(:contact_sheet_search, "")
     |> assign(:contact_search_results, [])}
  end

  def close_contact_search(socket) do
    # Unsubscribe from user-specific updates
    if socket.assigns.current_user do
      Phoenix.PubSub.unsubscribe(Friends.PubSub, "friends:user:#{socket.assigns.current_user.id}")
    end
    
    {:noreply,
     socket
     |> assign(:show_contact_search, false)
     |> assign(:contact_search_query, "")
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
     |> assign(:contact_search_query, query)
     |> assign(:contact_search_results, results)}
  end

  def send_friend_request(socket, user_id_str) do
    case safe_to_integer(user_id_str) do
      {:ok, user_id} ->
        case Social.add_friend(socket.assigns.current_user.id, user_id) do
          {:ok, _} ->
             # Refresh outgoing requests
             sent = Social.list_sent_friend_requests(socket.assigns.current_user.id)
             {:noreply, 
              socket 
              |> assign(:outgoing_friend_requests, sent)
              |> put_flash(:info, "Friend request sent!")}
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
             # Refresh friends and requests
             friends = Social.list_friends(socket.assigns.current_user.id)
             requests = Social.list_friend_requests(socket.assigns.current_user.id)
             {:noreply, 
              socket 
              |> assign(:friends, friends)
              |> assign(:pending_friend_requests, requests)
              |> put_flash(:info, "Friend accepted!")}
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
        {:noreply, assign(socket, :pending_friend_requests, requests)}
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
         |> put_flash(:info, "Friend removed")}
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
                outgoing = Social.list_sent_trust_requests(current_user.id)

                {:noreply,
                 socket
                 |> assign(:friend_search, "")
                 |> assign(:friend_search_results, [])
                 |> assign(:outgoing_trust_requests, outgoing)
                 |> put_flash(:info, "trust request sent")}

              {:error, :cannot_trust_self} ->
                {:noreply, put_flash(socket, :error, "can't trust yourself")}

              {:error, :max_trusted_friends} ->
                {:noreply, put_flash(socket, :error, "max 5 trusted friends")}

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
                # Refresh the pending requests and trusted friends list
                pending = Social.list_pending_trust_requests(current_user.id)
                trusted = Social.list_trusted_friends(current_user.id)
                trusted_ids = Enum.map(trusted, & &1.trusted_user_id)

                {:noreply,
                 socket
                 |> assign(:incoming_requests, pending)
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
                  {:noreply, put_flash(socket, :error, "not a trusted friend")}

                {:error, _} ->
                  {:noreply, put_flash(socket, :error, "already voted")}
              end
            end
        end
    end
  end
end
