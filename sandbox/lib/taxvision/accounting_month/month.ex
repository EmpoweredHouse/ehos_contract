defmodule Taxvision.AccountingMonth.Month do
  @moduledoc """
  Decides one company's month: it opens once, and only when the latest registry
  check of that month agreed — a check that failed and was retried with success
  opens it, as the workshop's retrigger does.
  """

  use Taxvision.Contracts.AccountingMonth, dcb: :accounting_month

  alias Taxvision.Contracts.RegistryWatch.Events.{
    RegistryDataConsistent,
    RegistryDiscrepancyDetected
  }

  @impl true
  def open_month(_command, %State{opened: true}), do: reject(:opens_once)

  def open_month(_command, %State{consistent: false}),
    do: reject(:opens_only_on_consistent_registry)

  def open_month(%OpenMonth{company_id: id, period_id: period}, _state),
    do: emit(%AccountingMonthOpened{company_id: id, period_id: period})

  @impl true
  def evolve(state, %RegistryDataConsistent{}), do: %{state | consistent: true}
  def evolve(state, %RegistryDiscrepancyDetected{}), do: %{state | consistent: false}
  def evolve(state, %AccountingMonthOpened{}), do: %{state | opened: true}
end
