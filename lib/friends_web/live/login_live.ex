defmodule FriendsWeb.LoginLive do
  use FriendsWeb, :live_view
  alias Friends.Social

  @impl true
  def mount(_params, session, socket) do
    # If already logged in, redirect to home
    if session["user_id"] do
      {:ok, socket |> redirect(to: "/")}
    else
      {:ok,
       socket
       |> assign(:page_title, "Login")
       |> assign(:username, "")
       |> assign(:step, :username)
       |> assign(:error, nil)
       |> assign(:user, nil)
       |> assign(:webauthn_challenge, nil)}
    end
  end

  @impl true
  def handle_event("check_username", %{"username" => username}, socket) do
    username = String.trim(username) |> String.downcase() |> String.replace_prefix("@", "")

    case Social.get_user_by_username(username) do
      nil ->
        {:noreply, assign(socket, :error, "User not found")}

      user ->
        credentials = Social.list_webauthn_credentials(user.id)

        if Enum.empty?(credentials) do
          {:noreply,
           assign(
             socket,
             :error,
             "No passkey registered for this account. Try account recovery or create a new account."
           )}
        else
          # Generate WebAuthn challenge
          challenge_options = Social.generate_webauthn_authentication_challenge(user)

          {:noreply,
           socket
           |> assign(:user, user)
           |> assign(:username, username)
           |> assign(:step, :webauthn)
           |> assign(:webauthn_challenge, challenge_options)
           |> assign(:error, nil)
           |> push_event("webauthn_login_challenge", %{options: challenge_options})}
        end
    end
  end

  @impl true
  def handle_event("webauthn_login_response", %{"credential" => credential_data}, socket) do
    user = socket.assigns.user
    challenge = socket.assigns.webauthn_challenge.challenge

    case Social.verify_webauthn_assertion(user.id, credential_data, challenge) do
      {:ok, _credential} ->
        # Register device session
        device_fingerprint = credential_data["rawId"]
        Social.register_user_device(user.id, device_fingerprint, "Web Browser", nil)

        {:noreply,
         socket
         |> assign(:step, :success)
         |> push_event("login_success", %{user_id: user.id})}

      {:error, reason} ->
        require Logger
        Logger.error("[LoginLive] WebAuthn verification failed: #{inspect(reason)}")

        {:noreply,
         socket
         |> assign(:step, :username)
         |> assign(:error, "Authentication failed. Please try again.")}
    end
  end

  @impl true
  def handle_event("webauthn_login_error", %{"error" => error}, socket) do
    {:noreply,
     socket
     |> assign(:step, :username)
     |> assign(:error, "Passkey error: #{error}")}
  end

  @impl true
  def handle_event("back", _params, socket) do
    {:noreply,
     socket
     |> assign(:step, :username)
     |> assign(:error, nil)
     |> assign(:user, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center p-4 relative">
      <div class="opal-bg"></div>
      
      <div class="w-full max-w-md relative z-10">
        <div class="text-center mb-8">
          <h1 class="text-3xl font-bold text-white mb-2">Login</h1>
          
          <p class="text-white/50">Sign in with your passkey</p>
        </div>
        
        <div class="aether-card p-6 space-y-6 bg-black/50">
          <%= case @step do %>
            <% :username -> %>
              <form phx-submit="check_username" class="space-y-4">
              <div>
                <label class="block text-xs text-white/40 mb-2 uppercase tracking-wider font-medium">Username</label>
                <input
                  type="text"
                  name="username"
                  value={@username}
                  placeholder="@username"
                  autocomplete="username"
                  autofocus
                  class="w-full px-4 py-3 bg-white/5 border border-white/10 rounded-xl text-white placeholder:text-white/30 focus:outline-none focus:border-white/30 focus:bg-white/[0.07] font-mono transition-all"
                />
              </div>
                
                <%= if @error do %>
                <div class="p-3 bg-red-500/10 border border-red-500/30 rounded-xl text-red-400 text-sm">
                  {@error}
                </div>
              <% end %>
                
                <button
                type="submit"
                class="w-full py-3 bg-white text-black font-bold rounded-xl hover:bg-white/90 hover:scale-[1.01] transition-all shadow-lg shadow-white/10"
                style="transition-timing-function: cubic-bezier(0.3, 1.5, 0.6, 1);"
              >
                Continue with Passkey
              </button>
            </form>
              
              <div class="text-center pt-4 border-t border-white/10">
              <p class="text-sm text-white/40 mb-3">Other options</p>
              
              <div class="space-y-2">
                <a
                  href="/recover"
                  class="block text-sm text-white/50 hover:text-white transition-colors"
                >
                  Recover account with trusted friends
                </a>
                <a
                  href="/register"
                  class="block text-sm text-white/50 hover:text-white transition-colors"
                >
                  Create new account
                </a>
              </div>
            </div>
            <% :webauthn -> %>
              <div id="webauthn-login-wrapper" phx-hook="WebAuthnLogin">
                <div class="text-center space-y-4">
                <div class="text-6xl mb-4">🔐</div>
                
                <h2 class="text-xl font-medium text-white">Use Your Passkey</h2>
                
                <p class="text-white/50">
                  Use your fingerprint, face, or security key to sign in as
                  <span class="text-white font-medium">@{@username}</span>
                </p>
                
                <div class="pt-4">
                  <div class="animate-pulse text-white/40">Waiting for passkey...</div>
                </div>
                
                <%= if @error do %>
                  <div class="p-3 bg-red-500/10 border border-red-500/30 rounded-xl text-red-400 text-sm">
                    {@error}
                  </div>
                <% end %>
                  
                  <button
                type="button"
                phx-click="back"
                class="text-sm text-white/50 hover:text-white transition-colors"
              >
                ← Back
              </button>
                </div>
              </div>
            <% :success -> %>
              <div id="webauthn-login-wrapper" phx-hook="WebAuthnLogin">
                <div class="text-center space-y-4">
                <div class="text-6xl mb-4">✅</div>
                
                <h2 class="text-xl font-medium text-white">Login Successful!</h2>
                
                <p class="text-white/50">Redirecting...</p>
              </div>
              </div>
          <% end %>
        </div>
        
        <div class="text-center mt-6">
          <a href="/" class="text-sm text-white/40 hover:text-white transition-colors">
            ← Back to home
          </a>
        </div>
      </div>
    </div>
    """
  end
end
