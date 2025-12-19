defmodule FriendsWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.
  Fluid Design system - glass surfaces, organic corners, spring animations.
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  @doc """
  Renders a simple button.
  """
  attr :type, :string, default: nil
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(disabled form name value)
  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button
      type={@type}
      class={[
        "px-5 py-2.5 text-sm font-bold tracking-wide rounded-xl transition-all",
        "bg-white text-black hover:bg-white/90 hover:scale-[1.02]",
        "shadow-lg shadow-white/10",
        "disabled:opacity-50 disabled:cursor-not-allowed disabled:hover:scale-100",
        @class
      ]}
      style="transition-timing-function: cubic-bezier(0.3, 1.5, 0.6, 1);"
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  Renders a secondary button.
  """
  attr :type, :string, default: nil
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(disabled form name value)
  slot :inner_block, required: true

  def button_secondary(assigns) do
    ~H"""
    <button
      type={@type}
      class={[
        "px-5 py-2.5 text-sm font-bold tracking-wide rounded-xl transition-all",
        "bg-white/5 border border-white/10 text-white/80",
        "hover:bg-white/10 hover:border-white/20 hover:text-white hover:scale-[1.02]",
        "disabled:opacity-50 disabled:cursor-not-allowed disabled:hover:scale-100",
        @class
      ]}
      style="transition-timing-function: cubic-bezier(0.3, 1.5, 0.6, 1);"
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  Renders an input with label.
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any
  attr :type, :string, default: "text"
  attr :field, Phoenix.HTML.FormField
  attr :errors, :list, default: []
  attr :class, :string, default: nil

  attr :rest, :global,
    include:
      ~w(accept autocomplete capture cols disabled form list max maxlength min minlength multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error/1))
    |> assign_new(:name, fn -> field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div>
      <label
        :if={@label}
        for={@id}
        class="block text-xs text-white/40 mb-2 uppercase tracking-wider font-medium"
      >
        {@label}
      </label>
      <textarea
        id={@id}
        name={@name}
        class={[
          "w-full px-4 py-3 rounded-xl text-sm text-white",
          "bg-white/5 border border-white/10",
          "placeholder:text-white/30",
          "focus:outline-none focus:border-white/30 focus:bg-white/[0.07]",
          "transition-all resize-none",
          @class
        ]}
        {@rest}
      >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(assigns) do
    ~H"""
    <div>
      <label
        :if={@label}
        for={@id}
        class="block text-xs text-white/40 mb-2 uppercase tracking-wider font-medium"
      >
        {@label}
      </label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class={[
          "w-full px-4 py-3 rounded-xl text-sm text-white",
          "bg-white/5 border border-white/10",
          "placeholder:text-white/30",
          "focus:outline-none focus:border-white/30 focus:bg-white/[0.07]",
          "transition-all",
          @class
        ]}
        {@rest}
      />
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  @doc """
  Renders error text.
  """
  slot :inner_block, required: true

  def error(assigns) do
    ~H"""
    <p class="mt-2 text-xs text-red-400/90 font-medium">{render_slot(@inner_block)}</p>
    """
  end

  @doc """
  Renders a modal.
  """
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :on_cancel, JS, default: %JS{}
  attr :container_class, :string, default: "w-full max-w-lg bg-neutral-900/95 backdrop-blur-xl border border-white/10 rounded-2xl p-6 relative shadow-2xl"
  attr :backdrop_class, :string, default: "bg-black/70 backdrop-blur-sm"
  slot :inner_block, required: true

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
      class="relative z-50 hidden"
      style="z-index: 9000;"
    >
      <div
        id={"#{@id}-bg"}
        class={["fixed inset-0 transition-opacity", @backdrop_class]}
        aria-hidden="true"
      />
      <div
        class="fixed inset-0 overflow-y-auto"
        aria-labelledby={"#{@id}-title"}
        aria-describedby={"#{@id}-description"}
        role="dialog"
        aria-modal="true"
        tabindex="0"
      >
        <div class="flex min-h-full items-center justify-center p-4">
          <div
            id={"#{@id}-container"}
            phx-window-keydown={JS.exec("data-cancel", to: "##{@id}")}
            phx-key="escape"
            phx-click-away={JS.exec("data-cancel", to: "##{@id}")}
            class={@container_class}
          >
            <button
              phx-click={JS.exec("data-cancel", to: "##{@id}")}
              type="button"
              class="absolute top-4 right-4 w-8 h-8 flex items-center justify-center rounded-full bg-white/5 text-white/50 hover:bg-white/10 hover:text-white transition-all z-50"
              aria-label="close"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
            {render_slot(@inner_block)}
          </div>
        </div>
      </div>
    </div>
    """
  end

  def show_modal(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.show(to: "##{id}")
    |> JS.show(
      to: "##{id}-bg",
      transition: {"transition-opacity ease-out duration-200", "opacity-0", "opacity-100"}
    )
    |> JS.show(
      to: "##{id}-container",
      transition:
        {"transition-all ease-out duration-200", "opacity-0 scale-95", "opacity-100 scale-100"}
    )
    |> JS.add_class("overflow-hidden", to: "body")
    |> JS.focus_first(to: "##{id}-container")
  end

  def hide_modal(js \\ %JS{}, id) do
    js
    |> JS.hide(
      to: "##{id}-bg",
      transition: {"transition-opacity ease-in duration-200", "opacity-100", "opacity-0"}
    )
    |> JS.hide(
      to: "##{id}-container",
      transition:
        {"transition-all ease-in duration-200", "opacity-100 scale-100", "opacity-0 scale-95"}
    )
    |> JS.hide(to: "##{id}", transition: {"block", "block", "hidden"})
    |> JS.remove_class("overflow-hidden", to: "body")
    |> JS.pop_focus()
  end

  @doc """
  Translates an error message.
  """
  def translate_error({msg, opts}) do
    if count = opts[:count] do
      Gettext.dngettext(FriendsWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(FriendsWeb.Gettext, "errors", msg, opts)
    end
  end
end
