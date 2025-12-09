defmodule FriendsWeb.Layouts do
  @moduledoc """
  Layout components for Friends app.
  """
  use FriendsWeb, :html

  embed_templates "layouts/*"

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
        "fixed top-4 right-4 z-50 px-4 py-3 text-sm cursor-pointer",
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

