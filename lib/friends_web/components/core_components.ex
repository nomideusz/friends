defmodule FriendsWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.
  Minimal, modern design with no icons - text-based interface.
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
        "px-4 py-2 text-sm font-medium transition-colors",
        "bg-white text-black hover:bg-neutral-200",
        "disabled:opacity-40 disabled:cursor-not-allowed",
        @class
      ]}
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
        "px-4 py-2 text-sm font-medium transition-colors",
        "border border-neutral-700 text-neutral-300 hover:border-neutral-500 hover:text-white",
        "disabled:opacity-40 disabled:cursor-not-allowed",
        @class
      ]}
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
  attr :rest, :global, include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength multiple pattern placeholder readonly required rows size step)

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
      <label :if={@label} for={@id} class="block text-xs text-neutral-500 mb-1 uppercase tracking-wide">
        {@label}
      </label>
      <textarea
        id={@id}
        name={@name}
        class={[
          "w-full px-3 py-2 bg-neutral-900 border border-neutral-800 text-white text-sm",
          "placeholder:text-neutral-600 focus:outline-none focus:border-neutral-600",
          "resize-none",
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
      <label :if={@label} for={@id} class="block text-xs text-neutral-500 mb-1 uppercase tracking-wide">
        {@label}
      </label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class={[
          "w-full px-3 py-2 bg-neutral-900 border border-neutral-800 text-white text-sm",
          "placeholder:text-neutral-600 focus:outline-none focus:border-neutral-600",
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
    <p class="mt-1 text-xs text-red-500">
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a modal.
  """
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :on_cancel, JS, default: %JS{}
  slot :inner_block, required: true

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
      class="relative z-50 hidden"
    >
      <div
        id={"#{@id}-bg"}
        class="fixed inset-0 bg-black/80 transition-opacity"
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
            class="w-full max-w-lg bg-neutral-900 border border-neutral-800 p-6"
          >
            <button
              phx-click={JS.exec("data-cancel", to: "##{@id}")}
              type="button"
              class="absolute top-4 right-4 text-neutral-500 hover:text-white"
              aria-label="close"
            >
              ×
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
    |> JS.show(to: "##{id}-bg", transition: {"transition-opacity ease-out duration-200", "opacity-0", "opacity-100"})
    |> JS.show(to: "##{id}-container", transition: {"transition-all ease-out duration-200", "opacity-0 scale-95", "opacity-100 scale-100"})
    |> JS.add_class("overflow-hidden", to: "body")
    |> JS.focus_first(to: "##{id}-container")
  end

  def hide_modal(js \\ %JS{}, id) do
    js
    |> JS.hide(to: "##{id}-bg", transition: {"transition-opacity ease-in duration-200", "opacity-100", "opacity-0"})
    |> JS.hide(to: "##{id}-container", transition: {"transition-all ease-in duration-200", "opacity-100 scale-100", "opacity-0 scale-95"})
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

