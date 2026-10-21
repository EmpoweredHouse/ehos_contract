defmodule Billing.Amounts do
  @moduledoc """
  **Invented.** The invariants of `Billing.Domain`'s amounts and quantities: neither is
  negative, so no usage line takes money off an invoice and no payment asks the gateway
  to pay out.
  """

  use Boundary, deps: [EhOsContract, Billing.Domain], exports: [Money, Quantity]
end

defmodule Billing.Amounts.Money do
  @moduledoc "The invariant of `Billing.Domain`'s value `:money`."

  use Billing.Domain, value: :money

  @impl true
  def not_negative(amount), do: amount >= 0
end

defmodule Billing.Amounts.Quantity do
  @moduledoc "The invariant of `Billing.Domain`'s value `:quantity`."

  use Billing.Domain, value: :quantity

  @impl true
  def not_negative(units), do: units >= 0
end
