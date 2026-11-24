defmodule Billing.Contracts do
  @moduledoc """
  **Invented.** The billing contracts, one per context: subscriptions and payments.
  The run across them is a process module, `Billing.Processes.Month`.
  """

  use Boundary,
    deps: [EhosContract],
    exports: [{Payments, []}, {Subscriptions, []}]
end
