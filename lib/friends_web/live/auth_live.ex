defmodule FriendsWeb.AuthLive do
  @moduledoc """
  Unified authentication page handling both login and registration.
  
  Flow:
  1. User enters username
  2. If username exists → login with passkey
  3. If username available → register with passkey
  """
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
       |> assign(:page_title, "New Internet")
       |> assign(:username, "")
       |> assign(:display_name, "")
       |> assign(:invite_code, "")
       |> assign(:step, :enter_username)
       |> assign(:mode, nil)  # :login or :register
       |> assign(:user, nil)
       |> assign(:webauthn_available, false)
       |> assign(:webauthn_challenge, nil)
       |> assign(:error, nil)
       |> assign(:checking_username, false)
       |> assign(:pending_room_code, nil)
       |> assign(:referrer, nil)}
    end
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

  # --- Event Handlers ---

  @impl true
  def handle_event("webauthn_available", %{"available" => available}, socket) do
    {:noreply, assign(socket, :webauthn_available, available)}
  end

  @impl true
  def handle_event("update_invite_code", %{"invite_code" => code}, socket) do
    {:noreply, assign(socket, :invite_code, String.trim(code))}
  end

  @impl true
  def handle_event("update_display_name", %{"display_name" => name}, socket) do
    {:noreply, assign(socket, :display_name, name)}
  end

  @impl true
  def handle_event("check_username", %{"username" => username}, socket) do
    username = String.trim(username) |> String.downcase() |> String.replace_prefix("@", "")

    cond do
      String.length(username) < 3 ->
        {:noreply,
         socket
         |> assign(:username, username)
         |> assign(:mode, nil)
         |> assign(:error, nil)}

      not Regex.match?(~r/^[a-z0-9_]+$/, username) ->
        {:noreply,
         socket
         |> assign(:username, username)
         |> assign(:mode, nil)
         |> assign(:error, "only lowercase letters, numbers, underscores")}

      String.length(username) > 20 ->
        {:noreply,
         socket
         |> assign(:username, username)
         |> assign(:mode, nil)
         |> assign(:error, "max 20 characters")}

      true ->
        case Social.get_user_by_username(username) do
          nil ->
            # Username available - registration mode
            {:noreply,
             socket
             |> assign(:username, username)
             |> assign(:mode, :register)
             |> assign(:user, nil)
             |> assign(:error, nil)}

          user ->
            # Username exists - login mode
            credentials = Social.list_webauthn_credentials(user.id)
            
            if Enum.empty?(credentials) do
              {:noreply,
               socket
               |> assign(:username, username)
               |> assign(:mode, nil)
               |> assign(:error, "Account has no passkey. Try recovery.")}
            else
              {:noreply,
               socket
               |> assign(:username, username)
               |> assign(:mode, :login)
               |> assign(:user, user)
               |> assign(:error, nil)}
            end
        end
    end
  end

  @impl true
  def handle_event("continue", _params, socket) do
    case socket.assigns.mode do
      :login -> start_login(socket)
      :register -> start_registration(socket)
      _ -> {:noreply, assign(socket, :error, "Please enter a valid username")}
    end
  end

  defp start_login(socket) do
    user = socket.assigns.user
    challenge_options = Social.generate_webauthn_authentication_challenge(user)

    {:noreply,
     socket
     |> assign(:step, :passkey)
     |> assign(:webauthn_challenge, challenge_options)
     |> push_event("webauthn_auth_challenge", %{
       mode: "login",
       options: challenge_options
     })}
  end

  defp start_registration(socket) do
    username = socket.assigns.username
    display_name = socket.assigns.display_name
    
    # Generate a temporary user struct for challenge generation
    temp_user = %{id: 0, username: username, display_name: display_name}
    challenge_options = Social.generate_webauthn_registration_challenge(temp_user)

    {:noreply,
     socket
     |> assign(:step, :passkey)
     |> assign(:webauthn_challenge, challenge_options.challenge)
     |> push_event("webauthn_auth_challenge", %{
       mode: "register",
       options: challenge_options
     })}
  end

  # Login response
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
         |> push_event("auth_success", %{user_id: user.id})}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:step, :enter_username)
         |> assign(:error, "Authentication failed. Please try again.")}
    end
  end

  # Registration response
  @impl true
  def handle_event("webauthn_register_response", %{"credential" => credential_data}, socket) do
    %{
      username: username,
      display_name: display_name,
      invite_code: invite_code,
      webauthn_challenge: challenge,
      referrer: referrer
    } = socket.assigns

    attrs = %{
      username: username,
      display_name: if(display_name == "", do: nil, else: display_name),
      public_key: nil,
      invite_code: invite_code,
      referrer: referrer
    }

    case Social.register_user_with_webauthn(attrs, credential_data, challenge) do
      {:ok, user} ->
        # Check if user should auto-join a room
        pending_room = socket.assigns.pending_room_code

        if pending_room do
          case Social.join_room(user, pending_room) do
            {:ok, _room} -> :ok
            _ -> :ok
          end
        end

        {:noreply,
         socket
         |> assign(:step, :success)
         |> assign(:user, user)
         |> push_event("auth_success", %{user_id: user.id})}

      {:error, :invalid_invite} ->
        {:noreply, assign(socket, :error, "invite code is no longer valid")}

      {:error, {:webauthn, reason}} ->
        {:noreply,
         socket
         |> assign(:step, :enter_username)
         |> assign(:error, "Passkey failed: #{format_webauthn_error(reason)}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        error = changeset.errors
          |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end)
          |> Enum.join(", ")
        {:noreply, assign(socket, :error, error)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, "Registration failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("webauthn_error", %{"error" => error}, socket) do
    message = case error do
      "Authentication cancelled" -> "Cancelled. Please try again."
      "Registration cancelled" -> "Cancelled. Please try again."
      _ -> "Passkey error: #{error}"
    end
    
    {:noreply,
     socket
     |> assign(:step, :enter_username)
     |> assign(:error, message)}
  end

  @impl true
  def handle_event("back", _params, socket) do
    {:noreply,
     socket
     |> assign(:step, :enter_username)
     |> assign(:error, nil)}
  end

  defp format_webauthn_error(:origin_mismatch), do: "Origin mismatch - please reload"
  defp format_webauthn_error(:rp_id_hash_mismatch), do: "Security verification failed"
  defp format_webauthn_error(:challenge_mismatch), do: "Challenge expired - please try again"
  defp format_webauthn_error({:webauthn_failed, reason}), do: format_webauthn_error(reason)
  defp format_webauthn_error(reason) when is_atom(reason), do: to_string(reason) |> String.replace("_", " ")
  defp format_webauthn_error(reason), do: inspect(reason)

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="auth-app"
      class="min-h-screen flex items-center justify-center p-4 relative"
      phx-hook="WebAuthnAuth"
    >
      <div class="opal-bg"></div>
      
      <div class="w-full max-w-sm relative z-10">
        <%= case @step do %>
          <% :enter_username -> %>
            <div class="text-center mb-8">
              <h1 class="text-3xl font-bold text-white" style="text-shadow: 0 0 40px rgba(255,255,255,0.3), 0 0 80px rgba(255,255,255,0.1); animation: gentle-pulse 3s ease-in-out infinite;">
                New Internet
              </h1>
            </div>
            
            <style>
              @keyframes gentle-pulse {
                0%, 100% { opacity: 1; }
                50% { opacity: 0.7; }
              }
            </style>
            
            <form phx-change="check_username" phx-submit="continue">
              <div class="relative mb-4">
                <span class="absolute left-4 top-1/2 -translate-y-1/2 text-neutral-500">@</span>
                <input
                  type="text"
                  name="username"
                  value={@username}
                  phx-debounce="300"
                  placeholder="username"
                  autocomplete="username"
                  autofocus
                  class={[
                    "w-full pl-8 pr-20 py-4 bg-black/30 border rounded-xl text-white placeholder:text-neutral-600 focus:outline-none font-mono text-lg transition-all",
                    @mode == :register && "border-emerald-500",
                    @mode == :login && "border-blue-500",
                    @mode == nil && "border-white/10 focus:border-white/30"
                  ]}
                />
                <%= if @mode == :register do %>
                  <span class="absolute right-4 top-1/2 -translate-y-1/2 text-emerald-500 text-sm font-medium">
                    available ✓
                  </span>
                <% end %>
                <%= if @mode == :login do %>
                  <span class="absolute right-4 top-1/2 -translate-y-1/2 text-blue-500 text-sm font-medium">
                    welcome back
                  </span>
                <% end %>
              </div>
              
              <%= if @error do %>
                <p class="text-red-500 text-xs mb-4 text-center">{@error}</p>
              <% end %>
              
              <%= if @mode do %>
                <%= if @webauthn_available do %>
                  <button
                    type="submit"
                    class="w-full py-4 bg-white text-black font-semibold rounded-xl hover:bg-neutral-200 transition-all cursor-pointer text-lg"
                  >
                    Continue
                  </button>
                <% else %>
                  <div class="w-full p-4 bg-red-900/20 border border-red-500/30 rounded-xl text-red-400 text-center text-sm">
                    Passkeys require Chrome, Safari, or Edge with biometrics enabled.
                  </div>
                <% end %>
              <% else %>
                <button
                  type="submit"
                  disabled
                  class="w-full py-4 bg-neutral-700 text-neutral-400 font-semibold rounded-xl cursor-not-allowed text-lg"
                >
                  Continue
                </button>
              <% end %>
            </form>
            
            <div class="text-center mt-6">
              <a
                href="/recover"
                class="text-xs text-neutral-500 hover:text-white transition-colors"
              >
                Recover Access →
              </a>
            </div>

          <% :passkey -> %>
            <div class="text-center space-y-6">
              <%!-- Minimal spinner --%>
              <div class="flex justify-center">
                <div class="w-12 h-12 border-2 border-white/20 border-t-white rounded-full animate-spin"></div>
              </div>
              
              <div>
                <p class="text-white font-medium">
                  @{@username}
                </p>
                <p class="text-neutral-500 text-sm mt-1">
                  <%= if @mode == :register, do: "Creating passkey...", else: "Authenticating..." %>
                </p>
              </div>
              
              <%= if @error do %>
                <div class="p-3 bg-red-900/30 border border-red-500/30 rounded-xl text-red-400 text-sm">
                  {@error}
                </div>
              <% end %>
              
              <button
                type="button"
                phx-click="back"
                class="text-sm text-neutral-500 hover:text-white transition-colors cursor-pointer"
              >
                Cancel
              </button>
            </div>

          <% :success -> %>
            <div class="text-center space-y-4">
              <div class="text-6xl mb-4">✅</div>
              
              <h2 class="text-xl font-medium text-white">
                <%= if @mode == :register, do: "Account Created!", else: "Welcome Back!" %>
              </h2>
              
              <p class="text-neutral-400">Redirecting...</p>
            </div>
        <% end %>
      </div>
    </div>
    """
  end
end
