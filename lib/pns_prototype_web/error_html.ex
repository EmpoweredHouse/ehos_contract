defmodule PnsPrototypeWeb.ErrorHTML do
  @moduledoc """
  Without this, an unhandled error masks itself as `ArgumentError: no
  html template defined` instead of the real exception — the same trap
  `packages/eh_os_contract_web`'s own test host hit twice before this config stopped
  being optional.
  """

  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)
end
