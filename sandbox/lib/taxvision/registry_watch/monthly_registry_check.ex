defmodule Taxvision.RegistryWatch.MonthlyRegistryCheck do
  @moduledoc """
  P1: on the first of the month, check the month before — August on 1 September,
  September on 1 October. The run keeps the date the next check is due: the first
  check sets it to the first of the next month, the check of the month it is for
  moves it one month on from itself, and any other check leaves it be. The month to
  check is the one that ended before that date, worked out without the database.
  """

  use Taxvision.Contracts.RegistryWatch, process_manager: :monthly_registry_check

  alias Taxvision.Periods

  @impl true
  def next_month(%State{company_id: id, check_at: at}),
    do: issue(%CheckRegistries{company_id: id, period_id: Periods.ended_before(at)})

  @impl true
  def evolve(%State{check_at: nil} = state, %DataCompletenessConfirmed{__meta__: meta}),
    do: %{state | check_at: Periods.next_month_start(meta.occurred_at)}

  def evolve(%State{check_at: at} = state, %DataCompletenessConfirmed{period_id: period}) do
    if period == Periods.ended_before(at),
      do: %{state | check_at: Periods.next_month_start(at)},
      else: state
  end
end
