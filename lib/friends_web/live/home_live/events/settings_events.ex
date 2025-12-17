defmodule FriendsWeb.HomeLive.Events.SettingsEvents do
  @moduledoc """
  Event handlers for Settings Modal and User Profile/Name management.
  """
  import Phoenix.Component
  import Phoenix.LiveView
  alias Friends.Social
  alias Friends.Social.Presence
  use FriendsWeb, :verified_routes

  # --- Settings Modal ---

  def open_devices_modal(socket) do
    # Refresh devices list just in case
    devices = Social.list_user_devices(socket.assigns.current_user.id)
    
    {:noreply,
     socket
     |> assign(:show_devices_modal, true)
     |> assign(:devices, devices)}
  end

  def close_devices_modal(socket) do
    {:noreply, assign(socket, :show_devices_modal, false)}
  end
  
  def revoke_device(socket, %{"id" => device_id}) do
    case Social.revoke_user_device(socket.assigns.current_user.id, device_id) do
      {:ok, _device} ->
        # Refresh list
        devices = Social.list_user_devices(socket.assigns.current_user.id)
        
        {:noreply,
         socket
         |> put_flash(:info, "Device revoked successfully")
         |> assign(:devices, devices)}
         
      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not revoke device")}
    end
  end

  def open_settings_modal(socket) do
    room = socket.assigns.room

    # Load room members if this is a private room
    members = 
      if room && room.is_private do
        Social.list_room_members(room.id)
      else
        []
      end

    {:noreply,
     socket
     |> assign(:show_settings_modal, true)
     |> assign(:settings_tab, "profile")
     |> assign(:room_members, members)}
  end

  def close_settings_modal(socket) do
    {:noreply,
     socket
     |> assign(:show_settings_modal, false)
     |> assign(:settings_tab, "profile")
     |> assign(:member_invite_search, "")
     |> assign(:member_invite_results, [])}
  end

  def switch_settings_tab(socket, tab) do
    {:noreply, assign(socket, :settings_tab, tab)}
  end

  # --- Name Modal / Profile ---

  def open_name_modal(socket) do
    {:noreply,
     socket
     |> assign(:show_name_modal, true)
     |> assign(:name_input, socket.assigns.user_name || "")}
  end

  def close_name_modal(socket) do
    {:noreply, assign(socket, :show_name_modal, false)}
  end

  def update_name_input(socket, name) do
    {:noreply, assign(socket, :name_input, name)}
  end

  def save_name(socket, name) do
    name = String.trim(name)
    name = if name == "", do: nil, else: String.slice(name, 0, 20)

    if name && Social.username_taken?(name, socket.assigns.user_id) do
      {:noreply, put_flash(socket, :error, "name taken")}
    else
      Social.save_username(socket.assigns.browser_id, name)

      Presence.update_user(
        self(),
        socket.assigns.room.code,
        socket.assigns.user_id,
        socket.assigns.user_color,
        name
      )

      {:noreply,
       socket
       |> assign(:user_name, name)
       |> assign(:show_name_modal, false)}
    end
  end

  # --- Sign Out ---

  def sign_out(socket) do
    # Push event to client to clear crypto identity
    # And redirect?
    # Original handle_event("sign_out") at 1970 pushed event "sign_out".
    # Original handle_event("sign_out") at 2195 pushed navigate.
    # We should do both? Or assume client handles it.
    # Usually client receives "sign_out", clears LocalStorage, then reloads or redirects.
    # But push_navigate might happen before client logic runs?
    # Let's keep the behave of the FIRST handler (at 1970) which was reachable.

    {:noreply,
     socket
     |> push_event("sign_out", %{})
     |> put_flash(:info, "Signing out...")}
  end
end
