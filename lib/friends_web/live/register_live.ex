defmodule FriendsWeb.RegisterLive do
  use FriendsWeb, :live_view
  alias Friends.Social

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:step, :username)
     |> assign(:invite_code, "")
     |> assign(:username, "")
     |> assign(:display_name, "")
     |> assign(:public_key, nil)
     |> assign(:crypto_ready, false)
     |> assign(:webauthn_available, false)
     |> assign(:auth_method, nil)
     |> assign(:webauthn_challenge, nil)
     |> assign(:error, nil)
     |> assign(:username_available, nil)
     |> assign(:checking_username, false)}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("set_public_key", %{"public_key" => public_key}, socket) do
    {:noreply,
     socket
     |> assign(:public_key, public_key)
     |> assign(:crypto_ready, true)
     |> assign(:error, nil)}
  end

  @impl true
  def handle_event("crypto_init_failed", %{"error" => error}, socket) do
    {:noreply,
     socket
     |> assign(:crypto_ready, false)
     |> assign(:error, "Crypto initialization failed: #{error}. Please try refreshing the page.")}
  end

  @impl true
  def handle_event("update_invite_code", %{"invite_code" => code}, socket) do
    {:noreply, assign(socket, :invite_code, String.trim(code))}
  end

  @impl true
  def handle_event("webauthn_available", %{"available" => available}, socket) do
    {:noreply, assign(socket, :webauthn_available, available)}
  end

  @impl true
  def handle_event("choose_auth_method", %{"method" => method}, socket) do
    {:noreply, assign(socket, :auth_method, method)}
  end

  @impl true
  def handle_event("start_webauthn_registration", _params, socket) do
    username = socket.assigns.username
    display_name = socket.assigns.display_name

    cond do
      is_nil(username) or username == "" ->
        {:noreply, assign(socket, :error, "choose a username first")}

      socket.assigns.username_available != true ->
        {:noreply, assign(socket, :error, "username not available")}

      true ->
        # Generate a temporary user struct for challenge generation
        temp_user = %{id: 0, username: username, display_name: display_name}
        challenge_options = Social.generate_webauthn_registration_challenge(temp_user)

        {:noreply,
         socket
         |> assign(:webauthn_challenge, challenge_options.challenge)
         |> push_event("webauthn_register_challenge", %{options: challenge_options})
         |> assign(:error, nil)}
    end
  end

  @impl true
  def handle_event("webauthn_register_response", %{"credential" => credential_data}, socket) do
    %{
      username: username,
      display_name: display_name,
      invite_code: invite_code,
      webauthn_challenge: challenge
    } = socket.assigns

    # Create user without public_key (WebAuthn-only user)
    attrs = %{
      username: username,
      display_name: if(display_name == "", do: nil, else: display_name),
      public_key: nil,
      invite_code: invite_code
    }

    cond do
      is_nil(credential_data) ->
        {:noreply, assign(socket, :error, "WebAuthn response missing credential")}

      is_nil(challenge) ->
        {:noreply, assign(socket, :error, "WebAuthn challenge expired, try again")}

      true ->
        case Social.register_user(attrs) do
          {:ok, user} ->
            case Social.verify_and_store_webauthn_credential(user.id, credential_data, challenge) do
              {:ok, _credential} ->
                {:noreply,
                 socket
                 |> assign(:step, :complete)
                 |> assign(:user, user)
                 |> push_event("registration_complete", %{user: %{id: user.id, username: user.username}})}

              {:error, reason} ->
                Friends.Repo.delete(user)
                {:noreply, assign(socket, :error, "WebAuthn registration failed: #{inspect(reason)}")}
            end

          {:error, :invalid_invite} ->
            {:noreply, assign(socket, :error, "invite code is no longer valid")}

          {:error, changeset} ->
            error =
              changeset.errors
              |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end)
              |> Enum.join(", ")
            {:noreply, assign(socket, :error, error)}
        end
    end
  end

  @impl true
  def handle_event("webauthn_register_error", %{"error" => error}, socket) do
    message =
      case error do
        "Registration cancelled" -> "WebAuthn was cancelled. You can retry or use Browser Key."
        _ -> "WebAuthn error: #{error}"
      end

    {:noreply, assign(socket, :error, message)}
  end

  @impl true
  def handle_event("noop", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("clear_identity", _params, socket) do
    {:noreply, push_event(socket, "clear_identity", %{})}
  end

  @impl true
  def handle_event("check_username", %{"username" => username}, socket) do
    username = String.trim(username) |> String.downcase()

    cond do
      Social.admin_username?(username) ->
        {:noreply,
         socket
         |> assign(:username, username)
         |> assign(:username_available, true)
         |> assign(:error, nil)}

      String.length(username) < 3 ->
        {:noreply,
         socket
         |> assign(:username, username)
         |> assign(:username_available, nil)
         |> assign(:error, nil)}

      not Regex.match?(~r/^[a-z0-9_]+$/, username) ->
        {:noreply,
         socket
         |> assign(:username, username)
         |> assign(:username_available, false)
         |> assign(:error, "only lowercase letters, numbers, underscores")}

      String.length(username) > 20 ->
        {:noreply,
         socket
         |> assign(:username, username)
         |> assign(:username_available, false)
         |> assign(:error, "max 20 characters")}

      true ->
        available = Social.username_available?(username)
        {:noreply,
         socket
         |> assign(:username, username)
         |> assign(:username_available, available)
         |> assign(:error, if(available, do: nil, else: "username taken"))}
    end
  end

  @impl true
  def handle_event("update_display_name", %{"display_name" => name}, socket) do
    {:noreply, assign(socket, :display_name, name)}
  end

  @impl true
  def handle_event("register", _params, socket) do
    %{
      username: username,
      display_name: display_name,
      public_key: public_key,
      invite_code: invite_code
    } = socket.assigns

    if is_nil(public_key) do
      {:noreply, assign(socket, :error, "crypto identity not ready, please refresh")}
    else
      attrs = %{
        username: username,
        display_name: if(display_name == "", do: nil, else: display_name),
        public_key: public_key,
        invite_code: invite_code
      }

      case Social.register_user(attrs) do
        {:ok, user} ->
          {:noreply,
           socket
           |> assign(:step, :complete)
           |> assign(:user, user)
           |> push_event("registration_complete", %{user: %{id: user.id, username: user.username}})}

        {:error, :invalid_invite} ->
          {:noreply, assign(socket, :error, "invite code is no longer valid")}

        {:error, changeset} ->
          error = 
            changeset.errors
            |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end)
            |> Enum.join(", ")
          {:noreply, assign(socket, :error, error)}
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="register-app" class="min-h-screen flex items-center justify-center p-4" phx-hook="RegisterApp">
      <div class="w-full max-w-md">
        <%= case @step do %>
          <% :username -> %>
            <div class="text-center mb-8">
              <h1 class="text-2xl font-medium text-white mb-2">join friends</h1>
              <p class="text-neutral-500 text-sm">invite is optional; pick a username to continue</p>
            </div>

            <div class="space-y-4">
              <div>
                <label class="block text-xs text-neutral-500 mb-2">invite code (optional)</label>
                <input
                  type="text"
                  name="invite_code"
                  value={@invite_code}
                  phx-input="update_invite_code"
                  placeholder="word-word-123"
                  autocomplete="off"
                  class="w-full px-4 py-3 bg-neutral-900 border border-neutral-800 text-white placeholder:text-neutral-700 focus:outline-none focus:border-neutral-600 font-mono"
                />
                <p class="mt-1 text-xs text-neutral-600">enter an invite for automatic trusted friend connection</p>
              </div>

              <form phx-change="check_username" phx-submit="noop" class="space-y-2">
                <div>
                  <label class="block text-xs text-neutral-500 mb-2">username</label>
                  <div class="relative">
                    <input
                      type="text"
                      name="username"
                      value={@username}
                      phx-debounce="300"
                      placeholder="yourname"
                      autocomplete="off"
                      autofocus
                      class={[
                        "w-full px-4 py-3 bg-neutral-900 border text-white placeholder:text-neutral-700 focus:outline-none font-mono",
                        @username_available == true && "border-green-600",
                        @username_available == false && "border-red-600",
                        @username_available == nil && "border-neutral-800 focus:border-neutral-600"
                      ]}
                    />
                    <%= if @username_available == true do %>
                      <span class="absolute right-3 top-1/2 -translate-y-1/2 text-green-500 text-xs">available</span>
                    <% end %>
                  </div>
                  <p class="mt-1 text-xs text-neutral-600">3-20 characters, lowercase, numbers, underscores</p>
                </div>
              </form>

              <div>
                <label class="block text-xs text-neutral-500 mb-2">display name (optional)</label>
                <input
                  type="text"
                  name="display_name"
                  value={@display_name}
                  phx-input="update_display_name"
                  placeholder="Your Name"
                  maxlength="50"
                  class="w-full px-4 py-3 bg-neutral-900 border border-neutral-800 text-white placeholder:text-neutral-700 focus:outline-none focus:border-neutral-600"
                />
              </div>

              <%= if @error do %>
                <p class="text-red-500 text-xs">{@error}</p>
              <% end %>

              <%= if @username_available == true do %>
                <div>
                  <label class="block text-xs text-neutral-500 mb-3">choose how to secure your account</label>
                  <div class="space-y-2">
                    <%!-- WebAuthn option --%>
                    <%= if @webauthn_available do %>
                      <button
                        type="button"
                        phx-click="start_webauthn_registration"
                        class="w-full p-4 bg-neutral-900 border border-neutral-800 hover:border-green-600 text-left transition-colors cursor-pointer group"
                      >
                        <div class="flex items-center gap-3">
                          <span class="text-2xl">🔐</span>
                          <div>
                            <div class="text-white font-medium group-hover:text-green-400 transition-colors">Hardware Key / Biometrics</div>
                            <div class="text-xs text-neutral-500">Touch ID, Face ID, or security key (recommended)</div>
                          </div>
                        </div>
                      </button>
                    <% end %>

                    <%!-- Browser crypto option --%>
                    <%= if @crypto_ready do %>
                      <form phx-submit="register">
                        <button
                          type="submit"
                          class="w-full p-4 bg-neutral-900 border border-neutral-800 hover:border-blue-600 text-left transition-colors cursor-pointer group"
                          phx-disable-with="creating..."
                        >
                          <div class="flex items-center gap-3">
                            <span class="text-2xl">🔑</span>
                            <div>
                              <div class="text-white font-medium group-hover:text-blue-400 transition-colors">Browser Key</div>
                              <div class="text-xs text-neutral-500">Key stored in this browser's storage</div>
                            </div>
                          </div>
                        </button>
                      </form>
                    <% else %>
                      <div class="w-full p-4 bg-neutral-900 border border-neutral-800 text-neutral-500">
                        <div class="flex items-center gap-3">
                          <span class="text-2xl opacity-50">🔑</span>
                          <div>
                            <div class="font-medium">Browser Key</div>
                            <div class="text-xs">initializing crypto...</div>
                          </div>
                        </div>
                      </div>
                    <% end %>
                  </div>
                </div>
              <% else %>
                <div class="w-full px-4 py-3 bg-neutral-800 text-neutral-500 text-center text-sm">
                  enter a valid username to continue
                </div>
              <% end %>
            </div>

            <button
              type="button"
              phx-click="clear_identity"
              class="mt-6 w-full text-center text-xs text-amber-600/60 hover:text-amber-500 cursor-pointer"
            >
              trouble logging in? clear identity & start fresh
            </button>

          <% :complete -> %>
            <div class="text-center">
              <div class="text-4xl mb-4">✓</div>
              <h1 class="text-2xl font-medium text-white mb-2">welcome, {@user.username}</h1>
              <p class="text-neutral-500 text-sm mb-8">your identity is secured</p>

              <a
                href="/"
                class="inline-block px-6 py-3 bg-white text-black font-medium hover:bg-neutral-200"
              >
                enter friends
              </a>

              <div class="mt-8 p-4 bg-neutral-900 border border-neutral-800 text-left">
                <p class="text-xs text-neutral-500 mb-2">next steps:</p>
                <ul class="text-xs text-neutral-400 space-y-1">
                  <li>• add 4-5 trusted friends for account recovery</li>
                  <li>• share your invite codes with friends</li>
                </ul>
              </div>
            </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Admin invite is unused in the current unified form; keep helper if needed later.
end


