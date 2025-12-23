defmodule FriendsWeb.PairLive do
  @moduledoc """
  LiveView for device pairing.
  Allows users to add a new device by entering a pairing token
  and completing WebAuthn registration.
  """
  use FriendsWeb, :live_view

  alias Friends.WebAuthn
  alias Friends.Social

  @impl true
  def mount(params, _session, socket) do
    token = params["token"] || ""
    
    socket = socket
      |> assign(:token_input, token)
      |> assign(:stage, if(token != "", do: :verifying, else: :input))
      |> assign(:error, nil)
      |> assign(:user, nil)
      |> assign(:challenge, nil)
      |> assign(:pairing, nil)
      |> assign(:success, false)

    # If token provided in URL, verify it
    socket = if token != "" do
      verify_token(socket, token)
    else
      socket
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"token" => token}, _uri, socket) when token != "" do
    {:noreply, verify_token(socket, token)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  defp verify_token(socket, token) do
    case WebAuthn.verify_pairing_token(token) do
      {:ok, pairing} ->
        # Generate WebAuthn registration challenge
        challenge = WebAuthn.generate_registration_challenge(pairing.user)
        
        socket
        |> assign(:stage, :register)
        |> assign(:user, pairing.user)
        |> assign(:pairing, pairing)
        |> assign(:challenge, challenge)
        |> assign(:error, nil)

      {:error, :invalid_token} ->
        socket
        |> assign(:stage, :input)
        |> assign(:error, "Invalid pairing code")

      {:error, :already_claimed} ->
        socket
        |> assign(:stage, :input)
        |> assign(:error, "This pairing code has already been used")

      {:error, :expired} ->
        socket
        |> assign(:stage, :input)
        |> assign(:error, "This pairing code has expired")
    end
  end

  @impl true
  def handle_event("verify_token", %{"token" => token}, socket) do
    {:noreply, verify_token(socket, token)}
  end

  def handle_event("update_token", %{"token" => token}, socket) do
    {:noreply, assign(socket, :token_input, String.upcase(token))}
  end

  def handle_event("complete_registration", %{"attestation" => attestation}, socket) do
    pairing = socket.assigns.pairing
    challenge = socket.assigns.challenge

    case WebAuthn.verify_registration(attestation, challenge.challenge, pairing.user_id) do
      {:ok, credential_data} ->
        # Claim the token and store credential
        case WebAuthn.claim_pairing_token(pairing.token, credential_data, "New Device") do
          {:ok, _credential} ->
            # Log in the user on this new device
            {:noreply,
             socket
             |> assign(:stage, :success)
             |> assign(:success, true)
             |> put_flash(:info, "Device paired successfully! You can now log in.")}

          {:error, reason} ->
            {:noreply,
             socket
             |> assign(:error, "Failed to complete pairing: #{inspect(reason)}")}
        end

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:error, "Registration failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-black flex items-center justify-center p-4">
      <div class="w-full max-w-md">
        <%!-- Logo --%>
        <div class="text-center mb-8">
          <h1 class="text-3xl font-bold text-white mb-2">Add Device</h1>
          <p class="text-white/50 text-sm">Link this device to your account</p>
        </div>

        <%!-- Card --%>
        <div class="bg-neutral-900/80 backdrop-blur-xl border border-white/10 rounded-3xl p-6 shadow-2xl">
          <%= case @stage do %>
            <% :input -> %>
              <%!-- Token Input Stage --%>
              <form phx-submit="verify_token" class="space-y-4">
                <div>
                  <label class="text-sm font-medium text-white/70 mb-2 block">Enter Pairing Code</label>
                  <input
                    type="text"
                    name="token"
                    value={@token_input}
                    phx-keyup="update_token"
                    placeholder="ABCD1234"
                    maxlength="8"
                    class="w-full bg-white/5 border border-white/10 rounded-xl px-4 py-3 text-white text-center text-2xl font-mono tracking-[0.3em] placeholder-white/20 focus:outline-none focus:border-white/30 uppercase"
                    autofocus
                  />
                </div>

                <%= if @error do %>
                  <div class="text-red-400 text-sm text-center py-2 px-4 bg-red-500/10 rounded-xl">
                    <%= @error %>
                  </div>
                <% end %>

                <button
                  type="submit"
                  class="w-full bg-white text-black font-semibold py-3 rounded-xl hover:bg-white/90 transition-colors"
                >
                  Continue
                </button>
              </form>

              <p class="text-white/30 text-xs text-center mt-4">
                Get the pairing code from your other device in Settings → Devices → Add Device
              </p>

            <% :verifying -> %>
              <%!-- Verifying Stage --%>
              <div class="text-center py-8">
                <div class="w-12 h-12 border-2 border-white/20 border-t-white rounded-full animate-spin mx-auto mb-4"></div>
                <p class="text-white/70">Verifying pairing code...</p>
              </div>

            <% :register -> %>
              <%!-- WebAuthn Registration Stage --%>
              <div class="space-y-4">
                <div class="text-center mb-6">
                  <div class="w-16 h-16 rounded-full bg-green-500/20 border border-green-500/30 flex items-center justify-center mx-auto mb-4">
                    <svg class="w-8 h-8 text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
                    </svg>
                  </div>
                  <h2 class="text-xl font-semibold text-white mb-2">Code Verified!</h2>
                  <p class="text-white/50 text-sm">
                    Linking to <span class="text-white font-medium">@{@user.username}</span>'s account
                  </p>
                </div>

                <%= if @error do %>
                  <div class="text-red-400 text-sm text-center py-2 px-4 bg-red-500/10 rounded-xl mb-4">
                    <%= @error %>
                  </div>
                <% end %>

                <div
                  id="webauthn-register"
                  phx-hook="WebAuthnPairing"
                  data-challenge={Jason.encode!(@challenge)}
                >
                  <button
                    type="button"
                    id="start-registration"
                    class="w-full bg-white text-black font-semibold py-3 rounded-xl hover:bg-white/90 transition-colors flex items-center justify-center gap-2"
                  >
                    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 11c0 3.517-1.009 6.799-2.753 9.571m-3.44-2.04l.054-.09A13.916 13.916 0 008 11a4 4 0 118 0c0 1.017-.07 2.019-.203 3m-2.118 6.844A21.88 21.88 0 0015.171 17m3.839 1.132c.645-2.266.99-4.659.99-7.132A8 8 0 008 4.07M3 15.364c.64-1.319 1-2.8 1-4.364 0-1.457.39-2.823 1.07-4" />
                    </svg>
                    Register This Device
                  </button>
                </div>

                <p class="text-white/30 text-xs text-center">
                  You'll be prompted to use Face ID, Touch ID, or your security key
                </p>
              </div>

            <% :success -> %>
              <%!-- Success Stage --%>
              <div class="text-center py-8">
                <div class="w-20 h-20 rounded-full bg-green-500/20 border-2 border-green-500/40 flex items-center justify-center mx-auto mb-6 animate-pulse">
                  <svg class="w-10 h-10 text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
                  </svg>
                </div>
                <h2 class="text-2xl font-bold text-white mb-2">Device Paired!</h2>
                <p class="text-white/50 mb-6">This device is now linked to your account</p>

                <.link
                  navigate="/"
                  class="inline-block bg-white text-black font-semibold px-8 py-3 rounded-xl hover:bg-white/90 transition-colors"
                >
                  Continue to App
                </.link>
              </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
