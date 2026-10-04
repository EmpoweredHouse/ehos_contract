defmodule AppuniteEquipment.Demanding.Demand do
  @moduledoc """
  Decides about one demand. Where it stands is the engine's, from the lifecycle:
  an order only while it waits, a close only while it is open or ordered (`from:`).
  Nothing finer than the status is left to decide.
  """

  use AppuniteEquipment.Contracts.Demands, aggregate: :demand

  @impl true
  def open_demand(%OpenDemand{} = demand, _state) do
    emit(%Opened{
      demand_id: demand.demand_id,
      employee_id: demand.employee_id,
      reason: demand.reason,
      starts_on: demand.starts_on
    })
  end

  @impl true
  def order_computer(%OrderComputer{} = order, _state),
    do: emit(%ComputerOrdered{demand_id: order.demand_id, profile: order.profile})

  @impl true
  def fulfil_demand(%FulfilDemand{} = issue, _state),
    do: emit(%Fulfilled{demand_id: issue.demand_id, computer_id: issue.computer_id})
end
