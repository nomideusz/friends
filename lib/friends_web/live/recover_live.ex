defmodule FriendsWeb.RecoverLive do
  @moduledoc """
  Recovery flow for users who lost their browser key.
  
  The process:
  1. User enters their username
  2. They get a new crypto key generated
  3. Their trusted friends are notified
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
     |> assign(:error, nil)}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
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
          {:noreply, assign(socket, :error, "not enough trusted friends (need 4+)")}
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
    recovery_status = Social.get_recovery_status(user.id)
    
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
          {:noreply, assign(socket, :recovery_status, recovery_status)}
      end
    else
      {:noreply, assign(socket, :recovery_status, recovery_status)}
    end
  end

  @impl true
  def handle_event("go_back", _params, socket) do
    {:noreply, assign(socket, :step, :username)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="recover-app" class="min-h-screen flex items-center justify-center p-4" phx-hook="RecoverApp">
      <div class="w-full max-w-md">
        <%= case @step do %>
          <% :username -> %>
            <div class="text-center mb-8">
              <h1 class="text-2xl font-medium text-white mb-2">recover account</h1>
              <p class="text-neutral-500 text-sm">lost your device? your friends can help</p>
            </div>

            <form phx-submit="lookup_user" class="space-y-4">
              <div>
                <label class="block text-xs text-neutral-500 mb-2">your username</label>
                <input
                  type="text"
                  name="username"
                  value={@username}
                  phx-change="update_username"
                  placeholder="@username"
                  autocomplete="off"
                  autofocus
                  class="w-full px-4 py-3 bg-neutral-900 border border-neutral-800 text-white placeholder:text-neutral-700 focus:outline-none focus:border-neutral-600 font-mono"
                />
              </div>

              <%= if @error do %>
                <p class="text-red-500 text-xs">{@error}</p>
              <% end %>

              <button
                type="submit"
                disabled={String.trim(@username) == ""}
                class="w-full px-4 py-3 bg-white text-black font-medium hover:bg-neutral-200 disabled:opacity-50 disabled:cursor-not-allowed cursor-pointer"
              >
                find account
              </button>
            </form>

            <div class="mt-8 text-center">
              <a href="/register" class="text-xs text-neutral-600 hover:text-white">
                don't have an account? register →
              </a>
            </div>

          <% :confirm -> %>
            <div class="text-center mb-8">
              <h1 class="text-2xl font-medium text-white mb-2">confirm recovery</h1>
              <p class="text-neutral-500 text-sm">we'll notify your trusted friends</p>
            </div>

            <div class="bg-neutral-900 border border-neutral-800 p-4 mb-6">
              <p class="text-sm text-neutral-300 mb-2">recovering: <span class="text-white">@{@user.username}</span></p>
              <p class="text-xs text-neutral-500">
                a new crypto key will be generated for this browser.
                your trusted friends will vote to confirm it's really you.
              </p>
            </div>

            <div class="bg-amber-500/10 border border-amber-500/20 p-4 mb-6">
              <p class="text-sm text-amber-400">⚠️ important</p>
              <p class="text-xs text-amber-500/80 mt-1">
                contact your trusted friends outside this app and ask them to confirm your recovery.
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
              <p class="text-neutral-500 text-sm">ask your trusted friends to confirm</p>
            </div>

            <%= if @recovery_status do %>
              <div class="bg-neutral-900 border border-neutral-800 p-4 mb-6">
                <div class="flex items-center justify-between mb-3">
                  <span class="text-sm text-neutral-400">confirmations</span>
                  <span class="text-lg font-mono text-white">{@recovery_status.confirmations} / 4</span>
                </div>
                
                <div class="w-full bg-neutral-800 h-2 rounded-full overflow-hidden">
                  <div 
                    class="bg-green-500 h-full transition-all"
                    style={"width: #{min(@recovery_status.confirmations * 25, 100)}%"}
                  />
                </div>
              </div>

              <button
                type="button"
                phx-click="check_status"
                class="w-full px-4 py-3 border border-neutral-700 text-neutral-300 font-medium hover:border-neutral-500 cursor-pointer"
              >
                check status
              </button>
            <% end %>

            <div class="mt-8 p-4 bg-neutral-900 border border-neutral-800">
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
                enter friends
              </a>

              <div class="mt-8 p-4 bg-neutral-900 border border-neutral-800 text-left">
                <p class="text-xs text-neutral-500 mb-2">what happened:</p>
                <ul class="text-xs text-neutral-400 space-y-1">
                  <li>• your trusted friends confirmed your identity</li>
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

