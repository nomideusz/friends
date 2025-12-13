defmodule FriendsWeb.HomeLive.Events.SessionEvents do
  @moduledoc """
  Event handlers and helpers for Session management, Device registration, and Identity bootstrapping.
  """
  import Phoenix.Component
  import Phoenix.LiveView
  import FriendsWeb.HomeLive.Helpers
  alias Friends.Social
  alias Friends.Social.Presence

  @colors colors()

  def set_user_id(socket, browser_id, fingerprint) do
    room = socket.assigns.room

    # On dashboard (index), room is nil - just return early
    if is_nil(room) do
      {:noreply, socket}
    else
      set_user_id_for_room(socket, room, browser_id, fingerprint)
    end
  end

  defp set_user_id_for_room(socket, room, browser_id, fingerprint) do
    # Register device for tracking
    {:ok, device, _status} = Social.register_device(fingerprint, browser_id)

    # If user is already authenticated via session cookie (set during WebAuthn login),
    # we just need to track presence. No additional client-side auth needed.
    case socket.assigns.current_user do
      nil ->
        # No authenticated user - use anonymous device identity
        user_id = device.master_id
        user_color = generate_user_color(user_id)
        user_name = device.user_name

        # Check access for private rooms (anonymous users can't access)
        can_access = Social.can_access_room?(room, nil)

        Presence.track_user(self(), room.code, user_id, user_color, user_name)
        viewers = Presence.list_users(room.code)

        {:noreply,
         socket
         |> assign(:user_id, user_id)
         |> assign(:user_color, user_color)
         |> assign(:user_name, user_name)
         |> assign(:auth_status, :anonymous)
         |> assign(:browser_id, browser_id)
         |> assign(:fingerprint, fingerprint)
         |> assign(:viewers, viewers)
         |> assign(:room_access_denied, not can_access)}

      user ->
        # User already authenticated via session cookie (WebAuthn login)
        # Just link device and refresh presence
        Social.link_device_to_user(browser_id, user.id)

        user_id = "user-#{user.id}"
        color = Enum.at(@colors, rem(user.id, length(@colors)))
        user_name = user.display_name || user.username

        can_access = Social.can_access_room?(room, user.id)

        if can_access do
          Presence.track_user(self(), room.code, user_id, color, user_name)
        end

        viewers = if can_access, do: Presence.list_users(room.code), else: []

        {:noreply,
         socket
         |> assign(:user_id, user_id)
         |> assign(:user_color, color)
         |> assign(:user_name, user_name)
         |> assign(:auth_status, :authed)
         |> assign(:browser_id, browser_id)
         |> assign(:fingerprint, fingerprint)
         |> assign(:viewers, viewers)
         |> assign(:room_access_denied, not can_access)}
    end
  end

  # Helper called from mount
  def maybe_bootstrap_identity(%{assigns: %{user_id: user_id}} = socket, _params)
       when not is_nil(user_id),
       do: socket

  def maybe_bootstrap_identity(socket, %{"browser_id" => browser_id} = params) do
    room = socket.assigns.room
    fingerprint = params["fingerprint"] || browser_id

    # We need to handle case where room might be nil (dashboard)?
    # Original logic in home_live.ex (Step 116) assumed room code existed?
    # Let's check original loop. Step 111, line 116 calls it.
    # Step 116 line 2758: `room = socket.assigns.room`.
    # Step 111 line 62: `assign(:room, nil)` in mount_dashboard.
    # If room is nil, line 2758 crashes??
    # No, `maybe_bootstrap_identity` is mostly for room joining?
    # `mount_room` calls it. `mount_dashboard` calls it too (Step 111 line 116).
    # If `room` is nil, `Social.can_access_room?` might fail or return false.
    # In `mount_dashboard`, `room` is nil.
    # If `maybe_bootstrap_identity` runs in dashboard, `room` is nil.
    # Line 2758: `room = socket.assigns.room`.
    # Line 2770: `Presence.track_user(..., room.code, ...)` -> CRASH if room is nil.
    # So `maybe_bootstrap_identity` logic seems designed for rooms.
    # But it's called in `mount_dashboard`!
    # Wait, `mount_dashboard` calls it with `get_connect_params`.
    # Maybe `get_connect_params` returns nil if not connected?
    # If not connected, `maybe_bootstrap_identity` likely matched first head (user_id nil?) No.
    # Ah, `get_connect_params` is nil on first HTTP render.
    # If `params` is nil, it falls through to catch-all (line 2799) -> returns socket.
    # So it only runs on connected mount.
    # Checks: does `mount_dashboard` pass `browser_id` in connect params?
    # Regardless, if it runs on dashboard, `room` is nil.
    # `Presence.track_user` needs `room.code`.
    # This implies `maybe_bootstrap_identity` logic in `home_live.ex` (line 2757+) assumes room exists?
    # Or maybe I blindly copied logic that only worked for rooms?
    # In `mount_dashboard` (Step 111), `socket` has `room: nil`.
    # If I access `dashboard`, `room` is nil.
    # If I am connected, `maybe_bootstrap_identity` runs.
    # It tries `room.code`.
    # This looks like a potential bug I found, or I am misreading.
    # Wait, `maybe_bootstrap_identity` is at bottom of `home_live.ex`.
    # Maybe `mount_dashboard` doesn't call it? Line 116 says it does.
    # `socket = maybe_bootstrap_identity(socket, get_connect_params(socket))`
    # If `room` is nil, `room.code` raises.
    # Unless... `mount_dashboard` calls it, but `browser_id` is NOT in params for dashboard?
    # The client hook `FriendsApp` likely sends `browser_id` only for rooms?
    # No, hook behaves typically.
    # Maybe `room` is not nil? No, line 62 `assign(:room, nil)`.
    # I will be defensive in `SessionEvents`. If `room` is nil, skip tracking presence/room stuff?
    # But `mount_dashboard` calls it.
    # I'll keep logic `if room do ... else ... end`.

    if room do
       # Original logic for room
       with {:ok, device, _} <- Social.register_device(fingerprint, browser_id),
            user_id when not is_nil(user_id) <- device.user_id,
            user when not is_nil(user) <- Social.get_user(user_id) do
         color = Enum.at(@colors, rem(user.id, length(@colors)))
         tracked_user_id = "user-#{user.id}"
         user_name = user.display_name || user.username

         viewers =
           if connected?(socket) do
             Presence.track_user(self(), room.code, tracked_user_id, color, user_name)
             Presence.list_users(room.code)
           else
             socket.assigns.viewers
           end

         private_rooms = if connected?(socket), do: Social.list_user_rooms(user.id), else: []

         socket
         |> assign(:current_user, user)
         |> assign(:pending_auth, nil)
         |> assign(:user_id, tracked_user_id)
         |> assign(:user_color, color)
         |> assign(:user_name, user_name)
         |> assign(:browser_id, browser_id)
         |> assign(:fingerprint, fingerprint)
         |> assign(:viewers, viewers)
         |> assign(:invites, Social.list_user_invites(user.id))
         |> assign(:trusted_friends, Social.list_trusted_friends(user.id))
         |> assign(:outgoing_trust_requests, Social.list_sent_trust_requests(user.id))
         |> assign(:pending_requests, Social.list_pending_trust_requests(user.id))
         |> assign(:recovery_requests, Social.list_recovery_requests_for_voter(user.id))
         |> assign(:user_private_rooms, private_rooms)
         |> assign(:room_access_denied, not Social.can_access_room?(room, user.id))
       else
         _ -> socket
       end
    else
       # Dashboard case - only bootstrap user, no room presence
       # But wait, dashboard uses `mount_dashboard` which sets user from Session.
       # `maybe_bootstrap_identity` is mostly for Room where user might be anonymous/device-based.
       # If dashboard, we rely on `load_session_user`.
       # So `maybe_bootstrap_identity` is likely redundant or should do nothing for dashboard if user is already loaded.
       # The clause `when not is_nil(user_id)` (line 2754) handles "if already loaded".
       # `mount_dashboard` loads user from session first.
       # So if user is logged in, `user_id` is set, and `maybe_bootstrap_identity` exits early.
       # If user is NOT logged in (guest on dashboard), `user_id` is nil.
       # Then `maybe_bootstrap_identity` runs.
       # But on dashboard, we might not want to bootstrap device identity?
       # The code crashes if it runs.
       # So I assume safely: if room is nil, return socket.
       socket
    end
  end

  def maybe_bootstrap_identity(socket, _), do: socket
end
