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
     |> assign(:pending_room_code, nil)
     |> assign(:referrer, nil)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # Check for join param (room to auto-join after registration)
    pending_room = params["join"]
    # Check for ref param (referrer username for auto-friendship)
    referrer = params["ref"]
    {:noreply,
     socket
     |> assign(:pending_room_code, pending_room)
     |> assign(:referrer, referrer)}
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
      webauthn_challenge: challenge,
      referrer: referrer
    } = socket.assigns

    # Create user without public_key (WebAuthn-only user)
    attrs = %{
      username: username,
      display_name: if(display_name == "", do: nil, else: display_name),
      public_key: nil,
      invite_code: invite_code,
      referrer: referrer
    }

    cond do
      is_nil(credential_data) ->
        {:noreply, assign(socket, :error, "WebAuthn response missing credential")}

      is_nil(challenge) ->
        {:noreply, assign(socket, :error, "WebAuthn challenge expired, try again")}

      true ->
        # Atomic registration: creates user AND credential together in a transaction
        # If WebAuthn fails, the user is never created (rolled back)
        case Social.register_user_with_webauthn(attrs, credential_data, challenge) do
          {:ok, user} ->
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

          {:error, :invalid_invite} ->
            {:noreply, assign(socket, :error, "invite code is no longer valid")}

          {:error, {:webauthn, reason}} ->
            {:noreply,
             assign(socket, :error, "Passkey registration failed: #{format_webauthn_error(reason)}")}

          {:error, {:credential_storage, _reason}} ->
            {:noreply,
             assign(socket, :error, "Failed to save passkey. Please try again.")}

          {:error, %Ecto.Changeset{} = changeset} ->
            error =
              changeset.errors
              |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end)
              |> Enum.join(", ")

            {:noreply, assign(socket, :error, error)}

          {:error, reason} ->
            {:noreply,
             assign(socket, :error, "Registration failed: #{inspect(reason)}")}
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
      class="min-h-screen flex items-center justify-center p-4 relative"
      phx-hook="RegisterApp"
    >
      <div class="opal-bg"></div>
      
      <div class="w-full max-w-md relative z-10">
        <%= case @step do %>
          <% :username -> %>
            <div class="text-center mb-8">
              <h1 class="text-2xl font-medium text-white mb-2">join new internet</h1>
              
              <p class="text-white/50 text-sm">invite is optional; pick a username to continue</p>
            </div>
            
            <div class="space-y-4">
              <div>
                <label class="block text-xs text-white/40 mb-2 uppercase tracking-wider font-medium">invite code (optional)</label>
                <input
                  type="text"
                  name="invite_code"
                  value={@invite_code}
                  phx-input="update_invite_code"
                  placeholder="word-word-123"
                  autocomplete="off"
                  class="w-full px-4 py-3 bg-white/5 border border-white/10 rounded-xl text-white placeholder:text-white/30 focus:outline-none focus:border-white/30 focus:bg-white/[0.07] font-mono transition-all"
                />
                <p class="mt-2 text-xs text-white/30">
                  enter an invite for automatic recovery contact connection
                </p>
              </div>
              
              <form phx-change="check_username" phx-submit="noop" class="space-y-2">
                <div>
                  <label class="block text-xs text-white/40 mb-2 uppercase tracking-wider font-medium">username</label>
                  <div class="relative">
                    <span class="absolute left-4 top-1/2 -translate-y-1/2 text-white/40 text-lg font-mono">@</span>
                    <input
                      type="text"
                      name="username"
                      value={@username}
                      phx-debounce="300"
                      placeholder="yourname"
                      autocomplete="off"
                      autofocus
                      class={[
                        "w-full pl-10 pr-20 py-3 bg-white/5 border rounded-xl text-white placeholder:text-white/30 focus:outline-none font-mono transition-all",
                        @username_available == true && "border-green-500/70 focus:border-green-500",
                        @username_available == false && "border-red-500/70 focus:border-red-500",
                        @username_available == nil && "border-white/10 focus:border-white/30"
                      ]}
                    />
                    <%= if @username_available == true do %>
                      <span class="absolute right-3 top-1/2 -translate-y-1/2 text-green-400 text-xs font-medium">
                        available
                      </span>
                    <% end %>
                  </div>
                  
                  <p class="mt-2 text-xs text-white/30">
                    3-20 characters, lowercase, numbers, underscores
                  </p>
                </div>
              </form>
              
              <div>
                <label class="block text-xs text-white/40 mb-2 uppercase tracking-wider font-medium">display name (optional)</label>
                <input
                  type="text"
                  name="display_name"
                  value={@display_name}
                  phx-input="update_display_name"
                  placeholder="Your Name"
                  maxlength="50"
                  class="w-full px-4 py-3 bg-white/5 border border-white/10 rounded-xl text-white placeholder:text-white/30 focus:outline-none focus:border-white/30 focus:bg-white/[0.07] transition-all"
                />
              </div>
              
              <%= if @error do %>
                <p class="text-red-400/90 text-xs font-medium">{@error}</p>
              <% end %>
              
              <%= if @username_available == true do %>
                <%= if @webauthn_available do %>
                  <button
                    type="button"
                    phx-click="start_webauthn_registration"
                    class="w-full p-4 bg-white text-black font-bold rounded-xl hover:bg-white/90 hover:scale-[1.01] transition-all cursor-pointer shadow-lg shadow-white/10"
                    style="transition-timing-function: cubic-bezier(0.3, 1.5, 0.6, 1);"
                  >
                    Create Account with Passkey
                  </button>
                  <p class="text-xs text-white/40 text-center">
                    Uses Touch ID, Face ID, Windows Hello, or security key
                  </p>
                <% else %>
                  <div class="w-full p-4 bg-red-500/10 border border-red-500/30 rounded-xl text-red-400 text-center">
                    <p class="font-medium mb-1">Passkeys not available</p>
                    
                    <p class="text-xs text-white/40">
                      Your browser doesn't support passkeys. Try using Chrome, Safari, or Edge on a device with biometrics.
                    </p>
                  </div>
                <% end %>
              <% else %>
                <div class="w-full px-4 py-3 bg-white/5 border border-white/10 text-white/40 text-center text-sm rounded-xl">
                  enter a valid username to continue
                </div>
              <% end %>
            </div>
            
            <div class="mt-6 text-center">
              <a href="/login" class="text-xs text-white/40 hover:text-white transition-colors">
                already have an account? login
              </a>
            </div>
          <% :complete -> %>
            <div class="text-center">
              <div class="text-4xl mb-4">✓</div>
              
              <h1 class="text-2xl font-medium text-white mb-2">welcome, {@user.username}</h1>
              
              <p class="text-white/50 text-sm mb-8">your passkey is set up</p>
              
              <a
                href={if @pending_room_code, do: "/r/#{@pending_room_code}", else: "/"}
                class="inline-block px-6 py-3 bg-white text-black font-bold rounded-xl hover:bg-white/90 hover:scale-[1.02] transition-all shadow-lg shadow-white/10"
                style="transition-timing-function: cubic-bezier(0.3, 1.5, 0.6, 1);"
              >
                <%= if @pending_room_code do %>
                  enter {@pending_room_code}
                <% else %>
                  enter new internet
                <% end %>
              </a>
              <div class="mt-8 p-4 bg-white/5 border border-white/10 rounded-xl text-left">
                <p class="text-xs text-white/40 mb-2 uppercase tracking-wider font-medium">next steps:</p>
                
                <ul class="text-xs text-white/50 space-y-1">
                  <li>• add recovery contacts for account recovery</li>
                  
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

  defp format_webauthn_error(:origin_mismatch), do: "Origin mismatch - please reload the page"
  defp format_webauthn_error(:rp_id_hash_mismatch), do: "Security verification failed"
  defp format_webauthn_error(:challenge_mismatch), do: "Challenge expired - please try again"
  defp format_webauthn_error({:webauthn_failed, reason}), do: format_webauthn_error(reason)
  defp format_webauthn_error(reason) when is_atom(reason), do: to_string(reason) |> String.replace("_", " ")
  defp format_webauthn_error(reason), do: inspect(reason)
end
