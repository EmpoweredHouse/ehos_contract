defmodule Taxvision.AccountingMonth.MatchEachTurnover do
  @moduledoc "P6: a statement's turnovers are matched, each one on its own."

  use Taxvision.Contracts.AccountingMonth, policy: :match_each_turnover

  @impl true
  def bank_turnover_list_created(%BankTurnoverListCreated{} = e),
    do:
      issue(
        for turnover <- e.turnovers do
          %RunMatching{company_id: e.company_id, period_id: e.period_id, turnover: turnover}
        end
      )
end
