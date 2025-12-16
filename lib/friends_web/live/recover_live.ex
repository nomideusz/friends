defmodule FriendsWeb.RecoverLive do
  @moduledoc """
  Recovery flow for users who lost their browser key.

  The process:
  1. User enters their username
  2. They get a new crypto key generated
  3. Their recovery contacts are notified
  4. 4 out of 5 friends must confirm to restore access
  """
  use FriendsWeb, :live_view
  alias Friends.Social

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:step, :username)
     |> assign(:username, "")
     |> assign(:user, nil)
     |> assign(:new_public_key, nil)
     |> assign(:recovery_status, nil)
     |> assign(:days_remaining, nil)
     |> assign(:error, nil)}
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
  def handle_event("update_username", %{"username" => username}, socket) do
    {:noreply, assign(socket, :username, String.trim(username))}
  end

  @impl true
  def handle_event("lookup_user", _params, socket) do
    username = socket.assigns.username

    case Social.get_user_by_username(username) do
      nil ->
        {:noreply, assign(socket, :error, "user not found")}

      user ->
        trusted_friends = Social.list_trusted_friends(user.id)

        if length(trusted_friends) < 4 do
          {:noreply, assign(socket, :error, "not enough recovery contacts (need 4+)")}
        else
          {:noreply,
           socket
           |> assign(:user, user)
           |> assign(:step, :confirm)
           |> assign(:error, nil)}
        end
    end
  end

  @impl true
  def handle_event("submit_recovery", _params, socket) do
    user = socket.assigns.user

    # Start recovery process
    case Social.request_recovery(user.username) do
      {:ok, updated_user} ->
        # Tell the client to generate a new key
        {:noreply,
         socket
         |> assign(:user, updated_user)
         |> assign(:step, :generating)
         |> push_event("generate_recovery_key", %{})}

      {:error, _} ->
        {:noreply, assign(socket, :error, "failed to start recovery")}
    end
  end

  @impl true
  def handle_event("set_public_key", %{"public_key" => public_key}, socket) do
    # Key is now generated - move to waiting state
    recovery_status = Social.get_recovery_status(socket.assigns.user.id)

    {:noreply,
     socket
     |> assign(:new_public_key, public_key)
     |> assign(:step, :waiting)
     |> assign(:recovery_status, recovery_status)}
  end

  @impl true
  def handle_event("check_status", _params, socket) do
    user = socket.assigns.user
    
    # Check for expiry first
    case Social.check_recovery_expiry(user) do
      {:expired, _updated_user} ->
        {:noreply,
         socket
         |> assign(:step, :username)
         |> assign(:error, "Recovery request expired. Please start again.")}

      {:ok, _user} ->
        recovery_status = Social.get_recovery_status(user.id)
        days_remaining = Social.recovery_days_remaining(user)

        if recovery_status.can_recover do
          # Recovery successful - update public key
          new_public_key = socket.assigns.new_public_key

          case Social.check_recovery_threshold(user.id, new_public_key) do
            {:ok, :threshold_met, _count} ->
              updated_user = Social.get_user(user.id)

              {:noreply,
               socket
               |> assign(:step, :complete)
               |> assign(:user, updated_user)}

            {:ok, :votes_recorded, _count} ->
              {:noreply,
               socket
               |> assign(:recovery_status, recovery_status)
               |> assign(:days_remaining, days_remaining)}
          end
        else
          {:noreply,
           socket
           |> assign(:recovery_status, recovery_status)
           |> assign(:days_remaining, days_remaining)}
        end
    end
  end

  @impl true
  def handle_event("go_back", _params, socket) do
    {:noreply, assign(socket, :step, :username)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="recover-app"
      class="min-h-screen flex items-center justify-center p-4 relative"
      phx-hook="RecoverApp"
    >
      <div class="opal-bg"></div>
      
      <div class="w-full max-w-sm relative z-10">
        <%= case @step do %>
          <% :username -> %>
            <div class="text-center mb-8">
              <h1 class="text-3xl font-bold text-white" style="text-shadow: 0 0 40px rgba(255,255,255,0.3), 0 0 80px rgba(255,255,255,0.1); animation: gentle-pulse 3s ease-in-out infinite;">
                Network Recovery
              </h1>
            </div>
            
            <style>
              @keyframes gentle-pulse {
                0%, 100% { opacity: 1; }
                50% { opacity: 0.7; }
              }
            </style>
            
            <form phx-submit="lookup_user">
              <div class="relative mb-4">
                <span class="absolute left-4 top-1/2 -translate-y-1/2 text-neutral-500">@</span>
                <input
                  type="text"
                  name="username"
                  value={@username}
                  phx-change="update_username"
                  placeholder="username"
                  autocomplete="off"
                  autofocus
                  class="w-full pl-8 pr-4 py-4 bg-black/30 border border-white/10 rounded-xl text-white placeholder:text-neutral-600 focus:outline-none focus:border-white/30 font-mono text-lg transition-all"
                />
              </div>
              
              <%= if @error do %>
                <p class="text-red-500 text-xs mb-4 text-center">{@error}</p>
              <% end %>
              
              <button
                type="submit"
                disabled={String.trim(@username) == ""}
                class={[
                  "w-full py-4 font-semibold rounded-xl text-lg transition-all",
                  if(String.trim(@username) == "", do: "bg-neutral-700 text-neutral-400 cursor-not-allowed", else: "bg-white text-black hover:bg-neutral-200 cursor-pointer")
                ]}
              >
                Continue
              </button>
            </form>
            
            <div class="text-center mt-6">
              <a href="/auth" class="text-xs text-neutral-500 hover:text-white transition-colors">
                ← Back to Sign In
              </a>
            </div>
          <% :confirm -> %>
            <div class="text-center mb-8">
              <h1 class="text-2xl font-medium text-white mb-2">confirm recovery</h1>
              
              <p class="text-neutral-500 text-sm">we'll notify your recovery contacts</p>
            </div>
            
            <div class="aether-card p-4 mb-6 bg-black/50">
              <p class="text-sm text-neutral-300 mb-2">
                recovering: <span class="text-white">@{@user.username}</span>
              </p>
              
              <p class="text-xs text-neutral-500">a new crypto key will be generated for this browser.
                your recovery contacts will vote to confirm it's really you.</p>
            </div>
            
            <div class="bg-amber-500/10 border border-amber-500/20 p-4 mb-6">
              <p class="text-sm text-amber-400">⚠️ important</p>
              
              <p class="text-xs text-amber-500/80 mt-1">
                contact your recovery contacts outside this app and ask them to confirm your recovery.
                you need 4 confirmations.
              </p>
            </div>
            
            <%= if @error do %>
              <p class="text-red-500 text-xs mb-4">{@error}</p>
            <% end %>
            
            <button
              type="button"
              phx-click="submit_recovery"
              class="w-full px-4 py-3 bg-amber-500 text-black font-medium hover:bg-amber-400 cursor-pointer"
            >
              start recovery
            </button>
            <button
              type="button"
              phx-click="go_back"
              class="mt-4 w-full text-center text-xs text-neutral-600 hover:text-white cursor-pointer"
            >
              ← back
            </button>
          <% :generating -> %>
            <div class="text-center">
              <div class="text-4xl mb-4 animate-pulse">🔐</div>
              
              <h1 class="text-2xl font-medium text-white mb-2">generating new key...</h1>
              
              <p class="text-neutral-500 text-sm">please wait</p>
            </div>
          <% :waiting -> %>
            <div class="text-center mb-8">
              <div class="text-4xl mb-4">⏳</div>
              
              <h1 class="text-2xl font-medium text-white mb-2">waiting for friends</h1>
              
              <p class="text-neutral-500 text-sm">ask your recovery contacts to confirm</p>
            </div>
            
            <%= if @recovery_status do %>
              <div class="aether-card p-4 mb-6 bg-black/50">
                <div class="flex items-center justify-between mb-3">
                  <span class="text-sm text-neutral-400">confirmations</span>
                  <span class="text-lg font-mono text-white">
                    {@recovery_status.confirmations} / 4
                  </span>
                </div>
                
                <div class="w-full bg-neutral-800 h-2 rounded-full overflow-hidden">
                  <div
                    class="bg-green-500 h-full transition-all"
                    style={"width: #{min(@recovery_status.confirmations * 25, 100)}%"}
                  />
                </div>
              </div>
              
              <%= if @days_remaining do %>
                <div class="mt-4 text-center">
                  <span class="text-xs text-amber-400">
                    ⏰ {@days_remaining} days remaining before request expires
                  </span>
                </div>
              <% end %>
              
              <button
                type="button"
                phx-click="check_status"
                class="w-full px-4 py-3 border border-neutral-700 text-neutral-300 font-medium hover:border-neutral-500 cursor-pointer"
              >
                check status
              </button>
            <% end %>
            
            <div class="mt-8 p-4 bg-white/5 border border-white/10 rounded-lg">
              <p class="text-xs text-neutral-500 mb-2">what to tell your friends:</p>
              
              <p class="text-xs text-neutral-400">
                "hey, i'm recovering my friends account. can you go to friends and confirm my recovery request? my username is @{@user.username}"
              </p>
            </div>
          <% :complete -> %>
            <div class="text-center">
              <div class="text-4xl mb-4">✓</div>
              
              <h1 class="text-2xl font-medium text-white mb-2">recovered!</h1>
              
              <p class="text-neutral-500 text-sm mb-8">your account is restored with a new key</p>
              
              <a
                href="/"
                class="inline-block px-6 py-3 bg-white text-black font-medium hover:bg-neutral-200"
              >
                enter new internet
              </a>
              <div class="mt-8 p-4 bg-white/5 border border-white/10 rounded-lg text-left">
                <p class="text-xs text-neutral-500 mb-2">what happened:</p>
                
                <ul class="text-xs text-neutral-400 space-y-1">
                  <li>• your recovery contacts confirmed your identity</li>
                  
                  <li>• a new crypto key was linked to your account</li>
                  
                  <li>• your old key is now invalid</li>
                </ul>
              </div>
            </div>
        <% end %>
      </div>
    </div>
    """
  end
end
