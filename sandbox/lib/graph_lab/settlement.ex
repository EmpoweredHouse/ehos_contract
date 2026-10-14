defmodule GraphLab.Settlement do
  @moduledoc """
  The implementation of `GraphLab.Contracts.Settlement`: Rehmed's, and the chase after a
  visit nobody settled.
  """

  use Boundary,
    deps: [EhOsContract, GraphLab.Contracts],
    exports: [VisitSettlement, DailyTotals, DailyTotalsFor, SettlementChase]
end
