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
                # Refresh the pending requests
                pending = Social.list_pending_trust_requests(current_user.id)

                {:noreply,
                 socket
                 |> assign(:pending_requests, pending)
                 |> put_flash(:info, "trust confirmed")}

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
