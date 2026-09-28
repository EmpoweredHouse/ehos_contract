defmodule Taxvision.AccountingMonth.MonthOpensOnConsistentRegistry do
  @moduledoc "03 §5, step 2: when the data agrees, the month opens."

  use Taxvision.Contracts.AccountingMonth, policy: :month_opens_on_consistent_registry

  alias Taxvision.Contracts.RegistryWatch.Events.RegistryDataConsistent

  @impl true
  def registry_data_consistent(%RegistryDataConsistent{company_id: id, period_id: period}),
    do: issue(%OpenMonth{company_id: id, period_id: period})
end
