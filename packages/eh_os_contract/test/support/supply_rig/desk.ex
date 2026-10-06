defmodule SupplyRig.Desk do
  @moduledoc """
  # THIS CONTRACT IS INVENTED. IT IS NOT CLIENT MATERIAL.

  Closing a visit takes a code from the clerk and whether its report went out from the
  host; noting an arrival takes the visit from the clerk and the moment from the host.
  """

  use EhOsContract.Contract, domain: SupplyRig.Domain, context: :desk, id: "supply_rig.desk"

  aggregate :visit, "Visit" do
    identity :visit_id

    command :close_visit, "Close the visit", by: :clerk, emits: :closed do
      field :code, :id
      field :reported, :boolean, supplied_by: :host
    end

    event :closed, "Closed" do
      field :code, :id
      field :reported, :boolean
    end

    event :arrival_noted, "Arrival noted", recorded_by: :clerk do
      field :arrived_at, :timestamp, supplied_by: :host
    end
  end

  read_model :visits, "Visits", projects: [:closed, :arrival_noted] do
    field :visit_id, :id
  end

  query :visits_of_desk, "Visits of the desk", reads: :visits, by: :clerk

  scenario "a closed visit carries whether its report went out" do
    command :close_visit, %{code: "A1", reported: true}
    expect :closed, %{code: "A1", reported: true}
  end

  # The read model keeps nothing: it is here so that the events have a reader.
  scenario "the desk's visits are nothing, since nothing is kept" do
    given :closed, %{code: "A1", reported: true}
    query :visits_of_desk, %{}
    answers []
  end

  process :desk, "Desk", accountable: :clerk do
    correlate :visit_id
  end
end

defmodule SupplyRig.Visit do
  @moduledoc "**Invented.** Closes a visit with what it is given."

  use SupplyRig.Desk, aggregate: :visit

  @impl true
  def close_visit(%CloseVisit{} = c, _state),
    do: emit(%Closed{visit_id: c.visit_id, code: c.code, reported: c.reported})
end

defmodule SupplyRig.Visits do
  @moduledoc "**Invented.** Keeps nothing."

  use SupplyRig.Desk, read_model: :visits

  @impl true
  def closed(_event), do: :ok

  @impl true
  def arrival_noted(_event), do: :ok
end

defmodule SupplyRig.VisitsOfDesk do
  @moduledoc "**Invented.** Answers nothing: nothing is kept."

  use SupplyRig.Desk, query: :visits_of_desk

  @impl true
  def visits_of_desk(%VisitsOfDesk{}, _ctx), do: []
end
