defmodule AppuniteEquipment.Demanding.WaitingList do
  @moduledoc """
  Answers who is waiting for a computer: the people starting soonest first, then
  those with no start date — a theft, a failure or an exchange, who are already
  working — in the order their demands were opened.
  """

  use AppuniteEquipment.Contracts.Demands, query: :waiting_list

  import Ecto.Query

  @impl true
  def waiting_list(%WaitingList{}, _ctx) do
    query =
      from(r in "appunite_equipment_demands",
        order_by: [asc_nulls_last: r.starts_on, asc: r.demand_id],
        select: %{
          demand_id: r.demand_id,
          employee_id: r.employee_id,
          reason: r.reason,
          starts_on: r.starts_on,
          status: r.status,
          profile: r.profile
        }
      )

    for row <- Application.fetch_env!(:eh_os_contract, :repo).all(query) do
      struct!(Row, %{
        row
        | reason: String.to_existing_atom(row.reason),
          status: String.to_existing_atom(row.status),
          profile: row.profile && String.to_existing_atom(row.profile)
      })
    end
  end
end
