defmodule AppuniteEquipment.Demanding.FulfilOnIssue do
  @moduledoc "The policy `fulfil_on_issue`: an issue closes the demand it answers."

  use AppuniteEquipment.Contracts.Demands, policy: :fulfil_on_issue

  @impl true
  def issued(%Issued{demand_id: demand, computer_id: computer}),
    do: issue(%FulfilDemand{demand_id: demand, computer_id: computer})
end
