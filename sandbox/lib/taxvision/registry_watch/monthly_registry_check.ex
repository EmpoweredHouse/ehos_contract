defmodule Taxvision.RegistryWatch.MonthlyRegistryCheck do
  @moduledoc """
  P1: on the first of the month, check the month before — August on 1 September,
  September on 1 October. Each check that starts sets the next one for the first of
  the following month, from when it started rather than from the period it named,
  and the month to check is the one that has ended by then — worked out from the
  date, without the database.
  """

  use Taxvision.Contracts.RegistryWatch, process_manager: :monthly_registry_check

  @impl true
  def next_month(%State{company_id: id, check_at: at}),
    do: issue(%CheckRegistries{company_id: id, period_id: Taxvision.Periods.ended_before(at)})

  @impl true
  def evolve(state, %DataCompletenessConfirmed{__meta__: meta}),
    do: %{state | check_at: Taxvision.Periods.next_month_start(meta.occurred_at)}
end
