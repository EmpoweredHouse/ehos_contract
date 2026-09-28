defmodule Taxvision.RegistryWatch.MonthlyRegistryCheck do
  @moduledoc """
  P1: on the first of the month, check the month before — August on 1 September,
  September on 1 October. Each check that starts sets the next one; the period's
  name is its identifier, so the next period and the day to check it are worked out
  here, without the database. The latest period only ever moves forward.
  """

  use Taxvision.Contracts.RegistryWatch, process_manager: :monthly_registry_check

  @impl true
  def next_month(%State{company_id: id, period_id: period}),
    do: issue(%CheckRegistries{company_id: id, period_id: Taxvision.Periods.next(period)})

  @impl true
  def evolve(state, %DataCompletenessConfirmed{period_id: period}) do
    latest = Enum.max([period, state.period_id || period])
    check_on = latest |> Taxvision.Periods.next() |> Taxvision.Periods.next()
    %{state | period_id: latest, check_at: Taxvision.Periods.first_moment(check_on)}
  end
end
