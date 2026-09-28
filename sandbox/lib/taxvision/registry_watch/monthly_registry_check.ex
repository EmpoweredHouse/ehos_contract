defmodule Taxvision.RegistryWatch.MonthlyRegistryCheck do
  @moduledoc """
  P1: a month after a company's check was logged, check the next period — August
  logged on 1 September, September on 1 October. The period's name is its
  identifier, so the next one is worked out here, without the database.
  """

  use Taxvision.Contracts.RegistryWatch, process_manager: :monthly_registry_check

  @impl true
  def next_month(%State{company_id: id, period_id: period}),
    do: issue(%CheckRegistries{company_id: id, period_id: Taxvision.Periods.next(period)})

  @impl true
  def evolve(state, %RegistryCheckLogged{period_id: period}), do: %{state | period_id: period}
end
