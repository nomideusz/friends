defmodule FriendsWeb.ErrorHTML do
  @moduledoc """
  Error pages.
  """
  use FriendsWeb, :html

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end

