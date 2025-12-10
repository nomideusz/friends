defmodule FriendsWeb.RegisterLive do
  use FriendsWeb, :live_view
  alias Friends.Social

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:step, :invite)
     |> assign(:invite_code, "")
     |> assign(:username, "")
     |> assign(:display_name, "")
     |> assign(:public_key, nil)
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
    {:noreply, assign(socket, :public_key, public_key)}
  end

  @impl true
  def handle_event("update_invite_code", %{"invite_code" => code}, socket) do
    {:noreply, assign(socket, :invite_code, code)}
  end

  @impl true
  def handle_event("check_invite", %{"invite_code" => code}, socket) do
    trimmed = String.trim(code)
    admin_code = admin_invite_code()

    cond do
      admin_code && (trimmed == "" || trimmed == admin_code) ->
        {:noreply,
         socket
         |> assign(:invite_code, admin_code)
         |> assign(:step, :username)
         |> assign(:error, nil)}

      true ->
        case Social.validate_invite(trimmed) do
          {:ok, _invite} ->
            {:noreply,
             socket
             |> assign(:invite_code, trimmed)
             |> assign(:step, :username)
             |> assign(:error, nil)}

          {:error, :invalid_invite} ->
            {:noreply, assign(socket, :error, "invalid invite code")}

          {:error, :invite_expired} ->
            {:noreply, assign(socket, :error, "invite code expired")}
        end
    end
  end

  @impl true
  def handle_event("go_back", _params, socket) do
    {:noreply, assign(socket, :step, :invite)}
  end

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
          <% :invite -> %>
            <div class="text-center mb-8">
              <h1 class="text-2xl font-medium text-white mb-2">friends</h1>
              <p class="text-neutral-500 text-sm">a network that requires friends</p>
            </div>

            <form phx-submit="check_invite" class="space-y-4">
              <div>
                <label class="block text-xs text-neutral-500 mb-2">invite code</label>
                <input
                  type="text"
                  name="invite_code"
                  value={@invite_code}
                  phx-change="update_invite_code"
                  placeholder="word-word-123"
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
                disabled={admin_invite_code() == nil and String.trim(@invite_code) == ""}
                class="w-full px-4 py-3 bg-white text-black font-medium hover:bg-neutral-200 disabled:opacity-50 disabled:cursor-not-allowed cursor-pointer"
              >
                continue
              </button>
            </form>

            <p class="mt-8 text-center text-xs text-neutral-600">
              no invite? ask a friend who's already here
            </p>

            <button 
              type="button"
              phx-click="clear_identity"
              class="mt-4 text-center text-xs text-amber-600/50 hover:text-amber-500 cursor-pointer w-full"
            >
              trouble logging in? clear identity & start fresh
            </button>

          <% :username -> %>
            <div class="text-center mb-8">
              <h1 class="text-2xl font-medium text-white mb-2">choose your name</h1>
              <p class="text-neutral-500 text-sm">this is how friends will find you</p>
            </div>

            <form phx-submit="register" class="space-y-4">
              <div>
                <label class="block text-xs text-neutral-500 mb-2">username</label>
                <div class="relative">
                  <input
                    type="text"
                    name="username"
                    value={@username}
                    phx-change="check_username"
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

              <div>
                <label class="block text-xs text-neutral-500 mb-2">display name (optional)</label>
                <input
                  type="text"
                  name="display_name"
                  value={@display_name}
                  phx-change="update_display_name"
                  placeholder="Your Name"
                  maxlength="50"
                  class="w-full px-4 py-3 bg-neutral-900 border border-neutral-800 text-white placeholder:text-neutral-700 focus:outline-none focus:border-neutral-600"
                />
              </div>

              <%= if @error do %>
                <p class="text-red-500 text-xs">{@error}</p>
              <% end %>

              <button
                type="submit"
                disabled={@username_available != true}
                class="w-full px-4 py-3 bg-white text-black font-medium hover:bg-neutral-200 disabled:opacity-50 disabled:cursor-not-allowed cursor-pointer"
              >
                create account
              </button>
            </form>

            <button
              type="button"
              phx-click="go_back"
              class="mt-4 w-full text-center text-xs text-neutral-600 hover:text-white cursor-pointer"
            >
              ← back
            </button>

          <% :complete -> %>
            <div class="text-center">
              <div class="text-4xl mb-4">✓</div>
              <h1 class="text-2xl font-medium text-white mb-2">welcome, {@user.username}</h1>
              <p class="text-neutral-500 text-sm mb-8">your identity is secured by cryptography</p>

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
                  <li>• your key is stored in this browser</li>
                </ul>
              </div>
            </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp admin_invite_code do
    Application.get_env(:friends, :admin_invite_code)
  end
end


