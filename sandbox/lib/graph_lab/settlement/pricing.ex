defmodule GraphLab.Settlement.Pricing do
  @moduledoc """
  The domain service `:pricing` of the test set (`GraphLab`): the patient pays what the
  payer does not cover, and never less than nothing.
  """

  use GraphLab.Contracts.Settlement, domain_service: :pricing

  @impl true
  def patient_part(price, covered), do: max(price - covered, 0)
end
