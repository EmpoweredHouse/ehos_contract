defmodule GraphLab.Till do
  @moduledoc """
  The implementation of `GraphLab.Contracts.Till`: the till's day, the cash refund, and
  the policy that owes a refund on a correction downwards.
  """

  use Boundary,
    deps: [EhOsContract, GraphLab.Contracts],
    exports: [TillDay, CashRefund, RefundOnCorrection]
end
