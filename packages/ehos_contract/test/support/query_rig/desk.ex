defmodule QueryRig.Desk do
  @moduledoc """
  # THIS CONTRACT IS INVENTED. IT IS NOT CLIENT MATERIAL.

  A desk a clerk notes visits at. Its one query takes a param of every shape the
  compiler accepts for a query (#618): each built-in type, a domain value resting on
  one, a list of either, and a value made of fields of one value each.
  """

  use EhosContract.Contract, domain: QueryRig.Domain, context: :desk, id: "query_rig.desk"

  aggregate :desk, "Desk" do
    identity :desk_id
    event :visit_noted, "Visit noted", recorded_by: :clerk
  end

  read_model :visits, "Visits", projects: :visit_noted do
    field :desk_id, :id
  end

  query :find_visits, "Find visits", reads: :visits, by: :clerk do
    param :text, :string
    param :count, :integer
    param :price, :decimal
    param :urgent, :boolean
    param :day, :date
    param :at, :timestamp
    param :id, :id
    param :desk, {:id, :desk}
    param :kind, {:enum, [:walk_in, :booked]}
    param :minutes, :minutes
    param :room, :room_id
    param :ids, {:list, :id}
    param :counts, {:list, :integer}
    param :kinds, {:list, {:enum, [:walk_in, :booked]}}
    param :rooms, {:list, :room_id}
    param :tags, :tags
    param :flags, {:list, :boolean}
    param :prices, {:list, :decimal}
    param :days, {:list, :date}
    param :ats, {:list, :timestamp}
    param :desks, {:list, {:id, :desk}}
    param :kind_values, {:list, :kind}
    param :window, :window
    param :need, :need
    param :need_ref, :need_ref
    param :slot, :slot
    param :missing, :string, optional: true
    param :missing_need, :need, optional: true
  end
end
