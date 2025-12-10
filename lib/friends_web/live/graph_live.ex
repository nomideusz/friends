defmodule FriendsWeb.GraphLive do
  use FriendsWeb, :live_view
  alias Friends.Social

  @colors ~w(#ef4444 #f97316 #eab308 #22c55e #14b8a6 #3b82f6 #8b5cf6 #ec4899)

  @impl true
  def mount(_params, session, socket) do
    user_id = session["user_id"]

    if user_id do
      user = Social.get_user(user_id)

      if user do
        trusted_friends = Social.list_trusted_friends(user_id)

        friends_data =
          Enum.map(trusted_friends, fn tf ->
            %{
              id: tf.trusted_user.id,
              username: tf.trusted_user.username,
              display_name: tf.trusted_user.display_name,
              color: user_color(tf.trusted_user.id)
            }
          end)

        current_user_data = %{
          id: user.id,
          username: user.username,
          display_name: user.display_name,
          color: user_color(user.id)
        }

        {:ok,
         socket
         |> assign(:current_user, user)
         |> assign(:friends, friends_data)
         |> assign(:current_user_data, current_user_data)
         |> assign(:page_title, "Friend Graph")}
      else
        {:ok,
         socket
         |> put_flash(:error, "User not found")
         |> redirect(to: "/")}
      end
    else
      {:ok,
       socket
       |> put_flash(:error, "You must be logged in to view your friend graph")
       |> redirect(to: "/")}
    end
  end

  @impl true
  def handle_event("node_clicked", %{"user_id" => user_id}, socket) do
    # Handle node clicks - could navigate to user profile, show details, etc.
    {:noreply,
     socket
     |> put_flash(:info, "Clicked on user #{user_id}")}
  end

  defp user_color(user_id) do
    Enum.at(@colors, rem(user_id, length(@colors)))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen text-white relative">
      <%!-- Animated opalescent background --%>
      <div class="opal-bg"></div>

      <%!-- Header --%>
      <header class="sticky top-0 z-40 backdrop-blur-md bg-black/30 border-b border-white/10">
        <div class="max-w-7xl mx-auto px-4 py-4">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-4">
              <a href="/" class="text-white/60 hover:text-white transition-colors">
                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
                </svg>
              </a>
              <h1 class="text-xl font-medium">Friend Graph</h1>
            </div>
            <div class="text-sm text-white/60">
              <%= length(@friends) %> <%= if length(@friends) == 1, do: "friend", else: "friends" %>
            </div>
          </div>
        </div>
      </header>

      <%!-- Main content --%>
      <main class="relative z-10">
        <div class="max-w-7xl mx-auto px-4 py-6">
          <%= if length(@friends) > 0 do %>
            <div class="bg-black/30 backdrop-blur-sm border border-white/10 rounded-lg overflow-hidden">
              <div
                id="friend-graph"
                phx-hook="FriendGraph"
                phx-update="ignore"
                data-current-user={Jason.encode!(@current_user_data)}
                data-friends={Jason.encode!(@friends)}
                class="w-full"
                style="height: 70vh; min-height: 500px;"
              >
              </div>
            </div>

            <%!-- Legend / Help --%>
            <div class="mt-6 p-4 bg-black/30 backdrop-blur-sm border border-white/10 rounded-lg">
              <h3 class="text-sm font-medium text-white/80 mb-3">How to use</h3>
              <ul class="text-sm text-white/60 space-y-1">
                <li>• Drag nodes to rearrange the graph</li>
                <li>• Double-click a node to focus on it</li>
                <li>• Scroll to zoom in/out</li>
                <li>• Click and drag the background to pan</li>
              </ul>
            </div>
          <% else %>
            <div class="text-center py-20">
              <div class="text-6xl mb-4">👥</div>
              <h2 class="text-xl font-medium text-white/80 mb-2">No friends yet</h2>
              <p class="text-white/60 mb-6">
                Add some friends to see your social graph come to life!
              </p>
              <a
                href="/"
                class="inline-flex items-center gap-2 px-4 py-2 bg-white text-black font-medium hover:bg-neutral-200 transition-colors"
              >
                Go back home
              </a>
            </div>
          <% end %>
        </div>
      </main>
    </div>
    """
  end
end
