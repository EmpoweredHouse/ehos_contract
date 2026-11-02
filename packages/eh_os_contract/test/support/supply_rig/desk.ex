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
end

defmodule SupplyRig.Visit do
  @moduledoc """
  **Invented.** Closes a visit with what it is given.

  A test can make the next closing append to the same stream behind the decision's
  back, `Process.put(:supply_rig_race, true)`, so that the append meets a stream that
  moved: the conflict dispatch retries.
  """

  use SupplyRig.Desk, aggregate: :visit

  @impl true
  def close_visit(%CloseVisit{} = c, _state) do
    if Process.delete(:supply_rig_race), do: race(c.visit_id)
    emit(%Closed{visit_id: c.visit_id, code: c.code, reported: c.reported})
  end

  # Another writer's event in the stream, appended at the version the decision read.
  defp race(id) do
    repo = Application.fetch_env!(:eh_os_contract, :repo)
    stream = EhOsContract.Key.stream(:visit, [id])
    version = length(EhOsContract.Store.read_stream(repo, stream, 0))

    {:ok, _} =
      EhOsContract.Store.append(
        repo,
        [
          %{
            type: "supply_rig.desk.closed",
            contract: EhOsContract.Model.fetch(SupplyRig.Desk).id,
            contract_version: "race",
            correlation_id: Ecto.UUID.generate(),
            actor: "system:race",
            occurred_at: EhOsContract.Clock.now(),
            payload: %{"visit_id" => id, "code" => "R1", "reported" => false}
          }
        ],
        {:stream, stream, version}
      )
  end
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
