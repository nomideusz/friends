defmodule FriendsWeb.LinkDeviceLive do
  @moduledoc """
  Device linking flow for WebAuthn-only authentication.

  With passkeys, device linking works differently:
  1. Passkeys often sync automatically via platform providers (iCloud Keychain, Google Password Manager)
  2. Users can add a new passkey on a new device if they're already logged in
  3. Account recovery via trusted friends is available if passkey sync isn't available

  This page guides users through these options.
  """
  use FriendsWeb, :live_view
  alias Friends.Social

  @impl true
  def mount(_params, session, socket) do
    user =
      case session["user_id"] do
        nil -> nil
        user_id -> Social.get_user(user_id)
      end

    {:ok,
     socket
     |> assign(:current_user, user)
     |> assign(:webauthn_available, false)
     |> assign(:webauthn_challenge, nil)
     |> assign(:error, nil)
     |> assign(:success, false)}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("webauthn_available", %{"available" => available}, socket) do
    {:noreply, assign(socket, :webauthn_available, available)}
  end

  @impl true
  def handle_event("add_passkey", _params, socket) do
    case socket.assigns.current_user do
      nil ->
        {:noreply, assign(socket, :error, "You must be logged in to add a passkey")}

      user ->
        # Generate WebAuthn registration challenge
        challenge_options = Social.generate_webauthn_registration_challenge(user)

        {:noreply,
         socket
         |> assign(:webauthn_challenge, challenge_options.challenge)
         |> assign(:error, nil)
         |> push_event("webauthn_link_challenge", %{options: challenge_options})}
    end
  end

  @impl true
  def handle_event("webauthn_link_response", %{"credential" => credential_data}, socket) do
    case socket.assigns do
      %{current_user: user, webauthn_challenge: challenge}
      when not is_nil(user) and not is_nil(challenge) ->
        case Social.verify_and_store_webauthn_credential(user.id, credential_data, challenge) do
          {:ok, _credential} ->
            {:noreply,
             socket
             |> assign(:success, true)
             |> assign(:error, nil)}

          {:error, reason} ->
            {:noreply, assign(socket, :error, "Failed to add passkey: #{inspect(reason)}")}
        end

      _ ->
        {:noreply, assign(socket, :error, "Invalid state - please refresh and try again")}
    end
  end

  @impl true
  def handle_event("webauthn_link_error", %{"error" => error}, socket) do
    message =
      case error do
        "Registration cancelled" -> "Passkey registration was cancelled. Please try again."
        _ -> "Passkey error: #{error}"
      end

    {:noreply, assign(socket, :error, message)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="link-device-app"
      class="min-h-screen flex items-center justify-center p-4"
      phx-hook="LinkDeviceApp"
    >
      <div class="w-full max-w-md">
        <%= if @success do %>
          <div class="text-center">
            <div class="text-4xl mb-4">✓</div>
            
            <h1 class="text-2xl font-medium text-white mb-2">Passkey Added!</h1>
            
            <p class="text-white/50 text-sm mb-8">You can now sign in with this device</p>
            
            <a
              href="/"
              class="inline-block px-6 py-3 bg-white text-black font-bold rounded-xl hover:bg-white/90 hover:scale-[1.02] transition-all shadow-lg shadow-white/10"
              style="transition-timing-function: cubic-bezier(0.3, 1.5, 0.6, 1);"
            >
              Continue to New Internet
            </a>
          </div>
        <% else %>
        <div class="text-center mb-8">
            <h1 class="text-2xl font-medium text-white mb-2">Access Your Account</h1>
            
            <p class="text-white/50 text-sm">Options for signing in on this device</p>
          </div>
          
          <div class="space-y-4">
            <%= if @current_user do %>
              <%!-- User is logged in - can add a new passkey --%>
              <div class="bg-white/5 border border-white/10 rounded-xl p-4">
                <h2 class="text-white font-medium mb-2">Add a Passkey</h2>
                
                <p class="text-xs text-white/40 mb-4">
                  Register a new passkey on this device for @{@current_user.username}
                </p>
                
                <%= if @webauthn_available do %>
                  <button
                    type="button"
                    phx-click="add_passkey"
                    class="w-full px-4 py-3 bg-white text-black font-bold rounded-xl hover:bg-white/90 hover:scale-[1.01] cursor-pointer transition-all shadow-lg shadow-white/10"
                    style="transition-timing-function: cubic-bezier(0.3, 1.5, 0.6, 1);"
                  >
                    Add Passkey to This Device
                  </button>
                <% else %>
                  <div class="p-3 bg-red-500/10 border border-red-500/30 rounded-xl text-red-400 text-sm">
                    Passkeys are not supported on this browser/device
                  </div>
                <% end %>
              </div>
            <% else %>
              <%!-- User is not logged in - show options --%>
              <div class="bg-white/5 border border-white/10 rounded-xl p-4">
                <h2 class="text-white font-medium mb-2">Passkey Sync</h2>
                
                <p class="text-xs text-white/40 mb-2">
                  If you use the same platform account on both devices, your passkey may already be synced:
                </p>
                
                <ul class="text-xs text-white/50 space-y-1 mb-4">
                  <li>• Apple devices: iCloud Keychain</li>
                  
                  <li>• Android/Chrome: Google Password Manager</li>
                  
                  <li>• Windows: Microsoft Account</li>
                </ul>
                
                <a
                  href="/login"
                  class="block w-full px-4 py-3 bg-white text-black font-bold text-center rounded-xl hover:bg-white/90 hover:scale-[1.01] transition-all shadow-lg shadow-white/10"
                  style="transition-timing-function: cubic-bezier(0.3, 1.5, 0.6, 1);"
                >
                  Try Signing In
                </a>
              </div>
              
              <div class="bg-white/5 border border-white/10 rounded-xl p-4">
                <h2 class="text-white font-medium mb-2">Account Recovery</h2>
                
                <p class="text-xs text-white/40 mb-4">
                  Lost access to your passkey? Your trusted friends can help you recover your account.
                </p>
                
                <a
                  href="/recover"
                  class="block w-full px-4 py-3 bg-white/5 border border-white/10 text-white font-medium text-center rounded-xl hover:bg-white/10 hover:border-white/20 transition-all"
                >
                  Start Recovery
                </a>
              </div>
              
              <div class="bg-white/5 border border-white/10 rounded-xl p-4">
                <h2 class="text-white font-medium mb-2">New User?</h2>
                
                <p class="text-xs text-white/40 mb-4">Create a new account with a passkey.</p>
                
                <a
                  href="/register"
                  class="block w-full px-4 py-3 bg-white/5 border border-white/10 text-white font-medium text-center rounded-xl hover:bg-white/10 hover:border-white/20 transition-all"
                >
                  Create Account
                </a>
              </div>
            <% end %>
            
            <%= if @error do %>
              <div class="p-3 bg-red-500/10 border border-red-500/30 rounded-xl text-red-400 text-sm">{@error}</div>
            <% end %>
          </div>
          
          <div class="mt-8 text-center">
            <a href="/" class="text-xs text-white/40 hover:text-white transition-colors">← back to friends</a>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
