defmodule AppuniteEquipment.Demanding.WaitingRows do
  @moduledoc """
  Projects who is waiting for a computer into `appunite_equipment_demands`: one row
  per demand while it is open or ordered, deleted when a computer is issued for it.
  """

  use AppuniteEquipment.Contracts.Demands, read_model: :waiting

  import Ecto.Query

  @table "appunite_equipment_demands"

  @impl true
  def opened(%Opened{} = demand) do
    repo().insert_all(
      @table,
      [
        %{
          demand_id: demand.demand_id,
          employee_id: demand.employee_id,
          reason: Atom.to_string(demand.reason),
          starts_on: demand.starts_on,
          status: "open"
        }
      ],
      on_conflict: :nothing
    )

    :ok
  end

  @impl true
  def computer_ordered(%ComputerOrdered{demand_id: id, profile: profile}) do
    repo().update_all(from(r in @table, where: r.demand_id == ^id),
      set: [status: "ordered", profile: Atom.to_string(profile)]
    )

    :ok
  end

  @impl true
  def fulfilled(%Fulfilled{demand_id: id}) do
    repo().delete_all(from(r in @table, where: r.demand_id == ^id))
    :ok
  end

  @impl true
  def reset do
    repo().delete_all(@table)
    :ok
  end

  defp repo, do: Application.fetch_env!(:eh_os_contract, :repo)
end
