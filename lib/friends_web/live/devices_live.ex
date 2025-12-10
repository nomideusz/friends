defmodule FriendsWeb.DevicesLive do
  use FriendsWeb, :live_view
  alias Friends.Social

  @impl true
  def mount(_params, session, socket) do
    user_id = session["user_id"]

    if user_id do
      user = Social.get_user(user_id)
      devices = Social.list_user_devices(user_id)

      {:ok,
       socket
       |> assign(:current_user, user)
       |> assign(:devices, devices)
       |> assign(:show_export, false)}
    else
      {:ok,
       socket
       |> put_flash(:error, "You must be logged in to manage devices")
       |> redirect(to: "/")}
    end
  end

  @impl true
  def handle_event("revoke_device", %{"device_id" => device_id}, socket) do
    device_id = String.to_integer(device_id)
    user_id = socket.assigns.current_user.id

    case Social.revoke_user_device(user_id, device_id) do
      {:ok, _device} ->
        devices = Social.list_user_devices(user_id)

        {:noreply,
         socket
         |> assign(:devices, devices)
         |> put_flash(:info, "Device revoked successfully")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to revoke device")}
    end
  end

  @impl true
  def handle_event("toggle_trust", %{"device_id" => device_id}, socket) do
    device_id = String.to_integer(device_id)
    user_id = socket.assigns.current_user.id

    device = Enum.find(socket.assigns.devices, &(&1.id == device_id))

    if device do
      case Social.update_device_trust(user_id, device_id, not device.trusted) do
        {:ok, _device} ->
          devices = Social.list_user_devices(user_id)

          {:noreply,
           socket
           |> assign(:devices, devices)
           |> put_flash(:info, "Device trust updated")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to update device trust")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("show_export", _params, socket) do
    {:noreply, assign(socket, :show_export, true) |> push_event("export_backup", %{})}
  end

  @impl true
  def handle_event("hide_export", _params, socket) do
    {:noreply, assign(socket, :show_export, false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen p-4 md:p-8">
      <div class="max-w-4xl mx-auto">
        <div class="mb-8">
          <h1 class="text-2xl font-medium text-white mb-2">Device Management</h1>
          <p class="text-neutral-500 text-sm">
            Manage devices that have access to your account
          </p>
        </div>

        <%= if @flash["info"] do %>
          <div class="mb-4 p-3 bg-green-900/30 border border-green-700 text-green-400 text-sm">
            {@flash["info"]}
          </div>
        <% end %>

        <%= if @flash["error"] do %>
          <div class="mb-4 p-3 bg-red-900/30 border border-red-700 text-red-400 text-sm">
            {@flash["error"]}
          </div>
        <% end %>

        <div class="mb-8 space-y-6">
          <%!-- WebAuthn / Hardware Keys --%>
          <div id="webauthn-section" phx-hook="WebAuthnManager" class="p-6 bg-neutral-900 border border-neutral-800">
            <h2 class="text-lg font-medium text-white mb-2">Hardware Security</h2>
            <p class="text-sm text-neutral-400 mb-4">
              Use Touch ID, Face ID, Windows Hello, or hardware security keys for enhanced protection.
            </p>
            <div id="webauthn-status" class="text-sm text-neutral-500 mb-4">
              Checking availability...
            </div>
            <button
              id="register-webauthn-btn"
              class="px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white font-medium hidden"
            >
              Register Hardware Key
            </button>
          </div>

          <%!-- Backup & Export --%>
          <div class="p-6 bg-neutral-900 border border-neutral-800">
            <h2 class="text-lg font-medium text-white mb-2">Backup & Export</h2>
            <p class="text-sm text-neutral-400 mb-4">
              Export your cryptographic keys for backup. Store this safely - anyone with access can impersonate you.
            </p>
            <div class="space-y-2">
              <button
                phx-click="show_export"
                class="px-4 py-2 bg-amber-600 hover:bg-amber-700 text-white font-medium"
              >
                Export Keys
              </button>
            </div>

            <%= if @show_export do %>
              <div id="export-container" phx-hook="ExportKeys" class="mt-4 p-4 bg-black/30 border border-amber-700">
                <p class="text-xs text-amber-400 mb-2">
                  Download your backup file and store it securely. You can also use QR codes to transfer to mobile devices.
                </p>
                <div id="export-qr-code" class="mt-4 flex justify-center"></div>
              </div>
            <% end %>
          </div>
        </div>

        <div class="bg-neutral-900 border border-neutral-800">
          <div class="p-6 border-b border-neutral-800">
            <h2 class="text-lg font-medium text-white">Trusted Devices</h2>
            <p class="text-sm text-neutral-500 mt-1">
              Devices that have authenticated with your account
            </p>
          </div>

          <%= if Enum.empty?(@devices) do %>
            <div class="p-6 text-center text-neutral-600">
              <p>No devices registered yet</p>
              <p class="text-xs mt-2">Devices will appear here after you log in</p>
            </div>
          <% else %>
            <div class="divide-y divide-neutral-800">
              <%= for device <- @devices do %>
                <div class="p-6">
                  <div class="flex items-start justify-between">
                    <div class="flex-1">
                      <div class="flex items-center gap-3">
                        <h3 class="font-medium text-white">{device.device_name || "Unknown Device"}</h3>
                        <%= if device.trusted do %>
                          <span class="text-xs px-2 py-1 bg-green-900/30 text-green-400 border border-green-700">
                            trusted
                          </span>
                        <% else %>
                          <span class="text-xs px-2 py-1 bg-neutral-800 text-neutral-500">
                            untrusted
                          </span>
                        <% end %>
                      </div>

                      <div class="mt-2 text-sm text-neutral-500 space-y-1">
                        <p>
                          Fingerprint: <span class="font-mono text-neutral-400">{String.slice(device.device_fingerprint, 0..15)}...</span>
                        </p>
                        <p>
                          First seen: <span class="text-neutral-400">{format_datetime(device.first_seen_at)}</span>
                        </p>
                        <p>
                          Last seen: <span class="text-neutral-400">{format_datetime(device.last_seen_at)}</span>
                        </p>
                      </div>
                    </div>

                    <div class="flex gap-2">
                      <button
                        phx-click="toggle_trust"
                        phx-value-device_id={device.id}
                        class="px-3 py-1 text-sm border border-neutral-700 hover:border-neutral-600 text-neutral-400 hover:text-white"
                      >
                        {if device.trusted, do: "Untrust", else: "Trust"}
                      </button>
                      <button
                        phx-click="revoke_device"
                        phx-value-device_id={device.id}
                        data-confirm="Are you sure? This device will need to re-authenticate."
                        class="px-3 py-1 text-sm border border-red-800 hover:border-red-700 text-red-500 hover:text-red-400"
                      >
                        Revoke
                      </button>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>

        <div class="mt-8">
          <a href="/" class="text-neutral-500 hover:text-white text-sm">
            ← Back to home
          </a>
        </div>
      </div>
    </div>
    """
  end

  defp format_datetime(nil), do: "never"

  defp format_datetime(datetime) do
    datetime
    |> DateTime.to_naive()
    |> NaiveDateTime.to_string()
    |> String.slice(0..18)
  end
end
