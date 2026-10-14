defmodule GraphLab.Settlement do
  @moduledoc """
  The implementation of `GraphLab.Contracts.Settlement`: the visit settlement's decision,
  the day's payments and their query, the chase after a visit nobody settled, and the
  payment rule the close decides with.
  """

  use Boundary,
    deps: [EhOsContract, GraphLab.Contracts],
    exports: [VisitSettlement, DailyTotals, DailyTotalsFor, SettlementChase, PaymentRules]
end
