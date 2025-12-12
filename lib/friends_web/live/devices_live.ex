defmodule FriendsWeb.DevicesLive do
  use FriendsWeb, :live_view
  alias Friends.Social

  @impl true
  def mount(_params, session, socket) do
    user_id = session["user_id"]

    if user_id do
      user = Social.get_user(user_id)
      devices = Social.list_user_devices(user_id)
      webauthn_credentials = Social.list_webauthn_credentials(user_id)

      {:ok,
       socket
       |> assign(:current_user, user)
       |> assign(:devices, devices)
       |> assign(:webauthn_credentials, webauthn_credentials)
       |> assign(:show_header_dropdown, false)
       |> assign(:show_user_dropdown, false)
       |> assign(:page_title, "Devices")}
    else
      {:ok,
       socket
       |> put_flash(:error, "You must be logged in to manage devices")
       |> redirect(to: "/")}
    end
  end

  @impl true
  def handle_event("toggle_user_dropdown", _params, socket) do
    {:noreply, assign(socket, :show_user_dropdown, !socket.assigns.show_user_dropdown)}
  end

  @impl true
  def handle_event("close_user_dropdown", _params, socket) do
    {:noreply, assign(socket, :show_user_dropdown, false)}
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
  def handle_event("request_webauthn_challenge", _params, socket) do
    user = socket.assigns.current_user
    challenge_options = Social.generate_webauthn_registration_challenge(user)

    {:noreply,
     socket
     |> assign(:webauthn_challenge, challenge_options.challenge)
     |> push_event("webauthn_challenge_generated", %{options: challenge_options})}
  end

  @impl true
  def handle_event("register_webauthn_credential", %{"credential" => credential_data}, socket) do
    user_id = socket.assigns.current_user.id
    challenge = socket.assigns.webauthn_challenge

    case Social.verify_and_store_webauthn_credential(user_id, credential_data, challenge) do
      {:ok, _credential} ->
        webauthn_credentials = Social.list_webauthn_credentials(user_id)

        {:noreply,
         socket
         |> assign(:webauthn_credentials, webauthn_credentials)
         |> assign(:webauthn_challenge, nil)
         |> put_flash(:info, "Hardware key registered successfully")
         |> push_event("webauthn_registration_complete", %{})}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to register hardware key")
         |> push_event("webauthn_registration_failed", %{})}
    end
  end

  @impl true
  def handle_event("delete_webauthn_credential", %{"credential_id" => credential_id_b64}, socket) do
    user_id = socket.assigns.current_user.id

    case Base.url_decode64(credential_id_b64, padding: false) do
      {:ok, credential_id} ->
        case Social.delete_webauthn_credential(user_id, credential_id) do
          {:ok, _} ->
            webauthn_credentials = Social.list_webauthn_credentials(user_id)

            {:noreply,
             socket
             |> assign(:webauthn_credentials, webauthn_credentials)
             |> put_flash(:info, "Hardware key removed")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to remove hardware key")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid credential ID")}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen p-4 md:p-8 text-neutral-200">
      <div class="max-w-2xl mx-auto space-y-8">
        
        <div class="flex items-center justify-between">
          <h1 class="text-2xl font-bold text-white">Devices</h1>
          <.link navigate={~p"/"} class="text-sm text-neutral-500 hover:text-white transition-colors">Done</.link>
        </div>

        <%!-- Hardware Keys --%>
        <section>
          <div class="flex items-center justify-between mb-4">
            <h2 class="font-medium text-white">Hardware Keys</h2>
            <div id="webauthn-section" phx-hook="WebAuthnManager" phx-update="ignore" class="flex items-center gap-3">
              <div id="webauthn-status" class="hidden text-xs text-neutral-500"></div>
              <button id="register-webauthn-btn" class="text-xs bg-white text-black px-3 py-1.5 rounded-lg hover:bg-neutral-200 transition-colors hidden">
                + Add Key
              </button>
            </div>
          </div>
          
          <div class="bg-neutral-900 rounded-2xl border border-white/5 overflow-hidden">
            <%= if @webauthn_credentials == [] do %>
              <div class="p-4 text-center text-sm text-neutral-500">No keys added.</div>
            <% else %>
              <div class="divide-y divide-white/5">
                <%= for cred <- @webauthn_credentials do %>
                  <div class="p-4 flex items-center justify-between">
                    <div>
                      <div class="text-sm font-medium text-white">{cred.name || "Security Key"}</div>
                      <div class="text-xs text-neutral-500">Last used: {format_datetime(cred.last_used_at)}</div>
                    </div>
                    <button phx-click="delete_webauthn_credential" phx-value-credential_id={Base.url_encode64(cred.credential_id, padding: false)} class="text-xs text-red-500 hover:text-red-400">Remove</button>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        </section>

        <%!-- Trusted Devices --%>
        <section>
          <h2 class="font-medium text-white mb-4">Active Sessions</h2>
          <div class="bg-neutral-900 rounded-2xl border border-white/5 overflow-hidden">
            <%= if @devices == [] do %>
              <div class="p-4 text-center text-sm text-neutral-500">No active sessions.</div>
            <% else %>
              <div class="divide-y divide-white/5">
                <%= for device <- @devices do %>
                  <div class="p-4 flex items-center justify-between">
                    <div>
                      <div class="font-medium text-white text-sm">{device.device_name || "Unknown Device"}</div>
                      <div class="text-xs text-neutral-500">
                        <%= if device.trusted, do: "Trusted", else: "Untrusted" %> • <!-- Last seen --> {format_datetime(device.last_seen_at)}
                      </div>
                    </div>
                    <div class="flex gap-3">
                      <button phx-click="toggle_trust" phx-value-device_id={device.id} class="text-xs text-neutral-400 hover:text-white transition-colors">
                        {if device.trusted, do: "Untrust", else: "Trust"}
                      </button>
                      <button phx-click="revoke_device" phx-value-device_id={device.id} class="text-xs text-red-500 hover:text-red-400 transition-colors">
                        Revoke
                      </button>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        </section>



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
