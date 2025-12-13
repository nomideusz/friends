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
     |> assign(:webauthn_available, false)
     |> assign(:webauthn_challenge, nil)
     |> assign(:error, nil)
     |> assign(:username_available, nil)
     |> assign(:checking_username, false)
     |> assign(:pending_room_code, nil)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # Check for join param (room to auto-join after registration)
    pending_room = params["join"]
    {:noreply, assign(socket, :pending_room_code, pending_room)}
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
                # Check if user should auto-join a room
                pending_room = socket.assigns.pending_room_code

                if pending_room do
                  case Social.join_room(user, pending_room) do
                    {:ok, _room} -> :ok
                    # Silently ignore join failures
                    _ -> :ok
                  end
                end

                {:noreply,
                 socket
                 |> assign(:step, :complete)
                 |> assign(:user, user)
                 |> push_event("registration_complete", %{
                   user: %{id: user.id, username: user.username}
                 })}

              {:error, reason} ->
                Friends.Repo.delete(user)

                {:noreply,
                 assign(socket, :error, "WebAuthn registration failed: #{inspect(reason)}")}
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
        "Registration cancelled" -> "Registration was cancelled. Please try again."
        _ -> "Registration error: #{error}"
      end

    {:noreply, assign(socket, :error, message)}
  end

  @impl true
  def handle_event("noop", _params, socket), do: {:noreply, socket}

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
  def render(assigns) do
    ~H"""
    <div
      id="register-app"
      class="min-h-screen flex items-center justify-center p-4"
      phx-hook="RegisterApp"
    >
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
                <p class="mt-1 text-xs text-neutral-600">
                  enter an invite for automatic trusted friend connection
                </p>
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
                      <span class="absolute right-3 top-1/2 -translate-y-1/2 text-green-500 text-xs">
                        available
                      </span>
                    <% end %>
                  </div>
                  
                  <p class="mt-1 text-xs text-neutral-600">
                    3-20 characters, lowercase, numbers, underscores
                  </p>
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
                <%= if @webauthn_available do %>
                  <button
                    type="button"
                    phx-click="start_webauthn_registration"
                    class="w-full p-4 bg-white text-black font-medium hover:bg-neutral-200 transition-colors cursor-pointer"
                  >
                    Create Account with Passkey
                  </button>
                  <p class="text-xs text-neutral-500 text-center">
                    Uses Touch ID, Face ID, Windows Hello, or security key
                  </p>
                <% else %>
                  <div class="w-full p-4 bg-neutral-900 border border-red-900 text-red-400 text-center">
                    <p class="font-medium mb-1">Passkeys not available</p>
                    
                    <p class="text-xs text-neutral-500">
                      Your browser doesn't support passkeys. Try using Chrome, Safari, or Edge on a device with biometrics.
                    </p>
                  </div>
                <% end %>
              <% else %>
                <div class="w-full px-4 py-3 bg-neutral-800 text-neutral-500 text-center text-sm">
                  enter a valid username to continue
                </div>
              <% end %>
            </div>
            
            <div class="mt-6 text-center">
              <a href="/login" class="text-xs text-neutral-500 hover:text-white transition-colors">
                already have an account? login
              </a>
            </div>
          <% :complete -> %>
            <div class="text-center">
              <div class="text-4xl mb-4">✓</div>
              
              <h1 class="text-2xl font-medium text-white mb-2">welcome, {@user.username}</h1>
              
              <p class="text-neutral-500 text-sm mb-8">your passkey is set up</p>
              
              <a
                href={if @pending_room_code, do: "/r/#{@pending_room_code}", else: "/"}
                class="inline-block px-6 py-3 bg-white text-black font-medium hover:bg-neutral-200"
              >
                <%= if @pending_room_code do %>
                  enter {@pending_room_code}
                <% else %>
                  enter friends
                <% end %>
              </a>
              <div class="mt-8 p-4 bg-neutral-900 border border-neutral-800 text-left">
                <p class="text-xs text-neutral-500 mb-2">next steps:</p>
                
                <ul class="text-xs text-neutral-400 space-y-1">
                  <li>• add trusted friends for account recovery</li>
                  
                  <li>• register additional passkeys on other devices</li>
                  
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
