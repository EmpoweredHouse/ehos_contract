defmodule PNS.Web.TestHost.ErrorHTML do
  @moduledoc """
  Without this, an unhandled error in the test host renders as
  `ArgumentError: no "500" html template defined` — the real exception,
  masked, exactly like the first time this package hit
  `Plug.CSRFProtection.InvalidCrossOriginRequestError` and the log showed
  only the masking error. Cheap enough to fix once, permanently.
  """

  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)
end
