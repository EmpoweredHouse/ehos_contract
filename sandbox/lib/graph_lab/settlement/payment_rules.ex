defmodule GraphLab.Settlement.PaymentRules do
  @moduledoc """
  The domain service `:payment_rules` of the test set (`GraphLab`), which the close of a
  visit's settlement decides with: payments pay a visit in full when they sum to its
  total.
  """

  use GraphLab.Contracts.Settlement, domain_service: :payment_rules

  @impl true
  def paid_in_full(paid, total), do: paid == total
end
