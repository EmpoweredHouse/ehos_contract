defmodule Rehmed.Settlement do
  @moduledoc """
  The implementation of `Rehmed.Contracts.Settlement` (`CTX-05`): the visit
  settlement's decision, which is pure, and `R-07`'s projection and query, which
  are the one place Rehmed's code writes a table of its own.

  Until 26 September 2026 this module was `decide/1`, the function v1's `rule`
  pointed at.
  """

  use Boundary,
    deps: [EhOsContract, Rehmed.Contracts],
    exports: [VisitSettlement, DailyTotals, DailyTotalsFor]
end
