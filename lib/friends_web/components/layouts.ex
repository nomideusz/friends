defmodule FriendsWeb.Layouts do
  @moduledoc """
  Layout components for Friends app.
  """
  use FriendsWeb, :html

  embed_templates "layouts/*"

  @doc """
  Renders the shared app header.
  This is used in the app layout to provide consistent navigation.
  Events bubble up to the parent LiveView.
  """
  attr :current_user, :any, default: nil
  attr :user_color, :string, default: "#888"
  attr :auth_status, :atom, default: :pending
  attr :page_title, :string, default: "Friends"
  attr :room, :any, default: nil
  attr :viewers, :list, default: []
  attr :user_rooms, :list, default: []
  attr :public_rooms, :list, default: []
  attr :pending_count, :integer, default: 0
  attr :recovery_count, :integer, default: 0
  attr :show_header_dropdown, :boolean, default: false
  attr :show_user_dropdown, :boolean, default: false
  attr :current_route, :string, default: "/"


  def shared_header(assigns) do
    # Determine the context title
    context_title = cond do
      assigns[:room] && assigns[:room].code == "lobby" -> "Public Square"
      assigns[:room] -> assigns[:room].name || assigns[:room].code
      assigns[:page_title] == "Contacts" -> "Contacts"
      assigns[:page_title] == "Devices" -> "Devices"
      assigns[:page_title] == "Home" -> "Home"
      true -> assigns[:page_title] || "Friends"
    end
    assigns = Phoenix.Component.assign(assigns, :context_title, context_title)

    ~H"""
    <header class="glass-strong border-b border-white/5 sticky top-0 z-40">
      <div class="max-w-[1600px] mx-auto px-4 sm:px-8 py-3">
        <div class="flex items-center justify-between gap-6 relative">
          
          <%!-- Left: Home Button (Dot) --%>
          <div class="flex items-center w-[120px]">
            <%= if @current_user do %>
              <.link navigate={~p"/"} class="group relative flex items-center justify-center w-10 h-10 -ml-2 rounded-full hover:bg-white/5 transition-all" title="Home">
                <div class="w-2.5 h-2.5 rounded-full bg-white/70 group-hover:bg-white group-hover:scale-110 transition-all shadow-[0_0_8px_rgba(255,255,255,0.2)]"></div>
              </.link>
            <% end %>
          </div>

          <%!-- Center: Context Title --%>
          <div class="absolute left-1/2 -translate-x-1/2 font-medium text-neutral-200 tracking-wide flex items-center justify-center gap-2 pointer-events-none">
            <%= if @room do %>
              <%= if @room.is_private do %>
                 <span class="text-neutral-500 text-xs">🔒</span>
              <% end %>
              <span>{@context_title}</span>
            <% else %>
              <span>{@context_title}</span>
            <% end %>
          </div>

          <%!-- Right: User Profile / Identity --%>
          <div class="flex items-center justify-end gap-6 w-[120px]">
            <%= if @auth_status == :pending do %>
              <span class="text-xs text-neutral-500">...</span>
            <% else %>
              <%= if @current_user do %>
                <div class="relative" phx-click-away="close_user_dropdown">
                  <button
                    type="button"
                    phx-click="toggle_user_dropdown"
                    class="flex items-center gap-2 text-sm font-medium text-neutral-400 hover:text-white transition-colors cursor-pointer"
                  >
                    <span>@{@current_user.username}</span>
                  </button>

                  <%= if @show_user_dropdown do %>
                    <div class="absolute top-10 right-0 w-48 bg-neutral-900 border border-white/10 rounded-xl shadow-xl overflow-hidden z-50 py-1">
                      
                      <.link navigate={~p"/network"} class="flex items-center gap-3 px-3 py-2 text-xs text-neutral-300 hover:bg-white/5 hover:text-white transition-colors cursor-pointer">
                        <span>👥</span> Contacts
                      </.link>
                      
                      <.link navigate={~p"/devices"} class="flex items-center gap-3 px-3 py-2 text-xs text-neutral-300 hover:bg-white/5 hover:text-white transition-colors cursor-pointer">
                        <span>🔐</span> Devices
                      </.link>
                      
                      <div class="h-px bg-white/5 my-1"></div>
                      
                      <button phx-click="sign_out" class="w-full flex items-center gap-3 px-3 py-2 text-xs text-red-400 hover:bg-white/5 hover:text-red-300 transition-colors cursor-pointer">
                        <span>🚪</span> Sign out
                      </button>
                    </div>
                  <% end %>
                </div>
              <% else %>
                <a href="/login" class="text-sm text-neutral-400 hover:text-white transition-colors">Login</a>
              <% end %>
            <% end %>
          </div>

        </div>
      </div>
    </header>
    """
  end

  @doc """
  Renders flash messages.
  """
  attr :flash, :map, required: true
  attr :kind, :atom, values: [:info, :error], default: :info
  attr :rest, :global

  def flash(assigns) do
    ~H"""
    <div
      :if={msg = Phoenix.Flash.get(@flash, @kind)}
      id={"flash-#{@kind}"}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> JS.hide(to: "#flash-#{@kind}")}
      role="alert"
      class={[
        "fixed top-4 right-4 z-[70] px-4 py-3 text-sm cursor-pointer",
        @kind == :info && "bg-neutral-900 text-white",
        @kind == :error && "bg-red-600 text-white"
      ]}
      {@rest}
    >
      {msg}
    </div>
    """
  end

  @doc """
  Renders all flash messages.
  """
  attr :flash, :map, required: true

  def flash_group(assigns) do
    ~H"""
    <.flash kind={:info} flash={@flash} />
    <.flash kind={:error} flash={@flash} />
    """
  end
end

