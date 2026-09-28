defmodule Taxvision.AccountingMonth do
  @moduledoc """
  The implementation of `Taxvision.Contracts.AccountingMonth` (03 §4.4): the month's
  decision over what its boundary read, the policy that opens it when the data
  agrees, and matching: its boundary, the policy that matches every turnover of a
  statement, and the pairing.

  Until 28 September 2026 the month was a row in `taxvision_accounting_months`,
  inserted by a v1 handler; it is its events now.
  """

  use Boundary,
    deps: [EhOsContract, Taxvision.Contracts],
    exports: [Month, MonthOpensOnConsistentRegistry, TurnoverMatching, MatchEachTurnover, Pairing]
end
