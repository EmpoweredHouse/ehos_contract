defmodule Billing.Processes do
  @moduledoc """
  **Invented.** Billing's run: one subscription's month, from its close to its payment.
  """

  use Boundary, deps: [EhosContract, Billing.Contracts], exports: []
end
