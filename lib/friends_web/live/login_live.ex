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
          {:noreply, assign(socket, :error, "No hardware key registered for this account. Try using 'Link Device' instead.")}
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
        # Create session token
        token = Base.encode64(:crypto.strong_rand_bytes(32))

        {:noreply,
         socket
         |> assign(:step, :success)
         |> push_event("login_success", %{
           user_id: user.id,
           token: token
         })}

      {:error, _reason} ->
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
     |> assign(:error, "Hardware key error: #{error}")}
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
          <p class="text-neutral-400">Sign in with your hardware key</p>
        </div>

        <div class="bg-neutral-900/80 backdrop-blur-sm border border-neutral-800 p-6 space-y-6">
          <%= case @step do %>
            <% :username -> %>
              <form phx-submit="check_username" class="space-y-4">
                <div>
                  <label class="block text-sm text-neutral-400 mb-2">Username</label>
                  <input
                    type="text"
                    name="username"
                    value={@username}
                    placeholder="@username"
                    autocomplete="username"
                    autofocus
                    class="w-full px-4 py-3 bg-black border border-neutral-700 text-white placeholder-neutral-600 focus:border-white focus:outline-none"
                  />
                </div>

                <%= if @error do %>
                  <div class="p-3 bg-red-900/50 border border-red-700 text-red-300 text-sm">
                    <%= @error %>
                  </div>
                <% end %>

                <button
                  type="submit"
                  class="w-full px-4 py-3 bg-white text-black font-medium hover:bg-neutral-200 transition-colors"
                >
                  Continue with Hardware Key
                </button>
              </form>

              <div class="text-center pt-4 border-t border-neutral-800">
                <p class="text-sm text-neutral-500 mb-3">Other options</p>
                <div class="space-y-2">
                  <a href="/link" class="block text-sm text-neutral-400 hover:text-white transition-colors">
                    📱 Link from another device
                  </a>
                  <a href="/recover" class="block text-sm text-neutral-400 hover:text-white transition-colors">
                    🔄 Recover account with trusted friends
                  </a>
                  <a href="/register" class="block text-sm text-neutral-400 hover:text-white transition-colors">
                    ✨ Create new account
                  </a>
                </div>
              </div>

            <% :webauthn -> %>
              <div id="webauthn-login" phx-hook="WebAuthnLogin" class="text-center space-y-4">
                <div class="text-6xl mb-4">🔐</div>
                <h2 class="text-xl font-medium text-white">Authenticate with Hardware Key</h2>
                <p class="text-neutral-400">
                  Please use your hardware key, fingerprint, or face recognition to sign in as <span class="text-white font-medium">@<%= @username %></span>
                </p>

                <div class="pt-4">
                  <div class="animate-pulse text-neutral-500">Waiting for authentication...</div>
                </div>

                <%= if @error do %>
                  <div class="p-3 bg-red-900/50 border border-red-700 text-red-300 text-sm">
                    <%= @error %>
                  </div>
                <% end %>

                <button
                  type="button"
                  phx-click="back"
                  class="text-sm text-neutral-400 hover:text-white transition-colors"
                >
                  ← Back
                </button>
              </div>

            <% :success -> %>
              <div class="text-center space-y-4">
                <div class="text-6xl mb-4">✅</div>
                <h2 class="text-xl font-medium text-white">Login Successful!</h2>
                <p class="text-neutral-400">Redirecting...</p>
              </div>
          <% end %>
        </div>

        <div class="text-center mt-6">
          <a href="/" class="text-sm text-neutral-500 hover:text-white transition-colors">
            ← Back to home
          </a>
        </div>
      </div>
    </div>
    """
  end
end
