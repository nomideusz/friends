defmodule FriendsWeb.LinkDeviceLive do
  @moduledoc """
  Device linking flow - transfer identity between browsers/devices.
  
  Two modes:
  1. Export - Generate QR code + PIN to share with new device
  2. Import - Scan QR code or enter code + PIN to link this device
  """
  use FriendsWeb, :live_view
  alias Friends.Social

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:mode, :choose)
     |> assign(:has_identity, false)
     |> assign(:qr_data_url, nil)
     |> assign(:pin, nil)
     |> assign(:transfer_code, nil)
     |> assign(:input_code, "")
     |> assign(:input_pin, "")
     |> assign(:error, nil)
     |> assign(:success, false)
     |> assign(:linked_user, nil)}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("check_identity", %{"has_identity" => has_identity}, socket) do
    {:noreply, assign(socket, :has_identity, has_identity)}
  end

  @impl true
  def handle_event("choose_export", _params, socket) do
    {:noreply,
     socket
     |> assign(:mode, :export)
     |> push_event("generate_transfer_code", %{})}
  end

  @impl true
  def handle_event("choose_import", _params, socket) do
    {:noreply, assign(socket, :mode, :import)}
  end

  @impl true
  def handle_event("transfer_code_generated", %{"pin" => pin, "code" => code, "qr_data_url" => qr_data_url}, socket) do
    {:noreply,
     socket
     |> assign(:pin, pin)
     |> assign(:transfer_code, code)
     |> assign(:qr_data_url, qr_data_url)}
  end

  @impl true
  def handle_event("update_input_code", %{"code" => code}, socket) do
    {:noreply, assign(socket, :input_code, String.trim(code))}
  end

  @impl true
  def handle_event("update_input_pin", %{"pin" => pin}, socket) do
    # Only allow digits, max 6
    clean_pin = pin |> String.replace(~r/[^0-9]/, "") |> String.slice(0, 6)
    {:noreply, assign(socket, :input_pin, clean_pin)}
  end

  @impl true
  def handle_event("submit_import", _params, socket) do
    code = socket.assigns.input_code
    pin = socket.assigns.input_pin

    if String.length(pin) != 6 do
      {:noreply, assign(socket, :error, "PIN must be 6 digits")}
    else
      {:noreply,
       socket
       |> assign(:error, nil)
       |> push_event("import_identity", %{code: code, pin: pin})}
    end
  end

  @impl true
  def handle_event("import_result", %{"success" => true, "public_key" => public_key}, socket) do
    # Check if there's a user with this public key
    user = Social.get_user_by_public_key(public_key)

    {:noreply,
     socket
     |> assign(:success, true)
     |> assign(:linked_user, user)}
  end

  @impl true
  def handle_event("import_result", %{"success" => false}, socket) do
    {:noreply, assign(socket, :error, "Invalid code or PIN")}
  end

  @impl true
  def handle_event("go_back", _params, socket) do
    {:noreply,
     socket
     |> assign(:mode, :choose)
     |> assign(:error, nil)
     |> assign(:qr_data_url, nil)
     |> assign(:pin, nil)
     |> assign(:transfer_code, nil)
     |> assign(:input_code, "")
     |> assign(:input_pin, "")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="link-device-app" class="min-h-screen flex items-center justify-center p-4" phx-hook="LinkDeviceApp">
      <div class="w-full max-w-md">
        <%= case @mode do %>
          <% :choose -> %>
            <div class="text-center mb-8">
              <h1 class="text-2xl font-medium text-white mb-2">link device</h1>
              <p class="text-neutral-500 text-sm">share your identity across browsers</p>
            </div>

            <div class="space-y-4">
              <%= if @has_identity do %>
                <button
                  type="button"
                  phx-click="choose_export"
                  class="w-full p-4 bg-neutral-900 border border-neutral-800 hover:border-neutral-600 text-left transition-colors cursor-pointer"
                >
                  <div class="flex items-center gap-3">
                    <span class="text-2xl">📤</span>
                    <div>
                      <div class="font-medium text-white">export to new device</div>
                      <div class="text-xs text-neutral-500">generate QR code to scan</div>
                    </div>
                  </div>
                </button>
              <% end %>

              <button
                type="button"
                phx-click="choose_import"
                class="w-full p-4 bg-neutral-900 border border-neutral-800 hover:border-neutral-600 text-left transition-colors cursor-pointer"
              >
                <div class="flex items-center gap-3">
                  <span class="text-2xl">📥</span>
                  <div>
                    <div class="font-medium text-white">import from another device</div>
                    <div class="text-xs text-neutral-500">scan QR code or enter code</div>
                  </div>
                </div>
              </button>
            </div>

            <div class="mt-8 text-center">
              <a href="/" class="text-xs text-neutral-600 hover:text-white">
                ← back to friends
              </a>
            </div>

          <% :export -> %>
            <div class="text-center mb-6">
              <h1 class="text-2xl font-medium text-white mb-2">export identity</h1>
              <p class="text-neutral-500 text-sm">scan this code on your other device</p>
            </div>

            <%= if @qr_data_url do %>
              <div class="bg-neutral-900 border border-neutral-800 p-6 mb-6">
                <div id="qr-container" phx-update="ignore" class="flex justify-center mb-4 bg-white p-4 rounded">
                  <div class="w-48 h-48 flex items-center justify-center text-neutral-400 text-sm">
                    <span id="qr-loading">loading QR...</span>
                  </div>
                </div>
                
                <div class="text-center mb-4">
                  <p class="text-xs text-neutral-500 mb-1">PIN (enter on other device)</p>
                  <p class="text-3xl font-mono font-bold text-white tracking-widest">{@pin}</p>
                </div>

                <div class="text-xs text-neutral-600 text-center">
                  this code expires when you leave this page
                </div>
              </div>

              <details class="mb-6">
                <summary class="text-xs text-neutral-500 cursor-pointer hover:text-neutral-400">
                  can't scan? copy code manually
                </summary>
                <div class="mt-2 p-2 bg-neutral-950 border border-neutral-800 rounded overflow-x-auto">
                  <code id="transfer-code" class="text-xs text-neutral-400 break-all">{@transfer_code}</code>
                </div>
              </details>
            <% else %>
              <div class="flex items-center justify-center py-12">
                <div class="text-neutral-500">generating...</div>
              </div>
            <% end %>

            <button
              type="button"
              phx-click="go_back"
              class="w-full text-center text-xs text-neutral-600 hover:text-white cursor-pointer"
            >
              ← back
            </button>

          <% :import -> %>
            <%= if @success do %>
              <div class="text-center">
                <div class="text-4xl mb-4">✓</div>
                <h1 class="text-2xl font-medium text-white mb-2">device linked!</h1>
                <%= if @linked_user do %>
                  <p class="text-neutral-500 text-sm mb-8">welcome back, @{@linked_user.username}</p>
                <% else %>
                  <p class="text-neutral-500 text-sm mb-8">identity imported successfully</p>
                <% end %>

                <a
                  href="/"
                  class="inline-block px-6 py-3 bg-white text-black font-medium hover:bg-neutral-200"
                >
                  enter friends
                </a>
              </div>
            <% else %>
              <div class="text-center mb-6">
                <h1 class="text-2xl font-medium text-white mb-2">import identity</h1>
                <p class="text-neutral-500 text-sm">paste the code from your other device</p>
              </div>

              <form phx-submit="submit_import" class="space-y-4">
                <div>
                  <label class="block text-xs text-neutral-500 mb-2">transfer code</label>
                  <textarea
                    name="code"
                    value={@input_code}
                    phx-change="update_input_code"
                    placeholder="paste the long code here..."
                    rows="4"
                    class="w-full px-3 py-2 bg-neutral-900 border border-neutral-800 text-sm text-white placeholder:text-neutral-700 focus:outline-none focus:border-neutral-600 font-mono resize-none"
                  >{@input_code}</textarea>
                </div>

                <div>
                  <label class="block text-xs text-neutral-500 mb-2">PIN (6 digits)</label>
                  <input
                    type="text"
                    name="pin"
                    value={@input_pin}
                    phx-change="update_input_pin"
                    placeholder="000000"
                    maxlength="6"
                    inputmode="numeric"
                    autocomplete="off"
                    class="w-full px-4 py-3 bg-neutral-900 border border-neutral-800 text-white text-center text-2xl font-mono tracking-widest placeholder:text-neutral-700 focus:outline-none focus:border-neutral-600"
                  />
                </div>

                <%= if @error do %>
                  <p class="text-red-500 text-xs">{@error}</p>
                <% end %>

                <button
                  type="submit"
                  disabled={@input_code == "" || String.length(@input_pin) != 6}
                  class="w-full px-4 py-3 bg-white text-black font-medium hover:bg-neutral-200 disabled:opacity-40 disabled:cursor-not-allowed cursor-pointer"
                >
                  link device
                </button>
              </form>

              <button
                type="button"
                phx-click="go_back"
                class="mt-4 w-full text-center text-xs text-neutral-600 hover:text-white cursor-pointer"
              >
                ← back
              </button>
            <% end %>
        <% end %>
      </div>
    </div>
    """
  end
end

