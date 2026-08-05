defmodule PNS.GraphTest do
  @moduledoc """
  Whether a graph can be built from the contract, and whether overlaying it on the
  log makes sense.

  This is the question "does this have a chance" put as a test rather than as an
  opinion. There is no dashboard and deliberately will not be one at this step —
  first check whether the difference is signal.
  """

  use Taxvision.DataCase, async: false

  alias Taxvision.Contracts.AccountingMonth

  test "the static graph comes from the registry, that is, from the binary" do
    graph = PNS.Graph.static()

    # The registry scans the **whole binary**, and since stage 1.2 there are two
    # contracts in it: this one and the universality gate fixture. Counting nodes
    # without narrowing to a contract was the hidden assumption "there is only
    # one".
    ours = Enum.filter(graph.nodes, &(&1.contract == AccountingMonth))
    assert length(ours) == length(AccountingMonth.events())

    edges = MapSet.new(graph.edges, &{&1.from, &1.to})
    assert MapSet.member?(edges, {:registry_data_consistent, :monthly_tasks_generated})
    assert MapSet.member?(edges, {:monthly_tasks_generated, :accounting_month_opened})
    assert MapSet.member?(edges, {:registry_discrepancy_detected, :discrepancy_notification_sent})

    async = Enum.filter(graph.edges, & &1.async)
    assert Enum.map(async, & &1.from) == [:registry_discrepancy_detected]
  end

  test "before any run everything is dead and nothing is drift" do
    overlay = PNS.Graph.overlay()

    assert Enum.all?(overlay, &(&1.state == :dead))
    assert Enum.all?(overlay, &(&1.count == 0))
  end

  test "after a run the edges become confirmed and the untaken ones stay dead" do
    {:ok, _} = Taxvision.Api.open_month(accountant("c-1"), %{company_id: "c-1", period: "2026-07"})

    overlay = PNS.Graph.overlay()
    by_edge = Map.new(overlay, &{{&1.from, &1.to}, &1})

    assert by_edge[{:registry_data_consistent, :monthly_tasks_generated}].state == :confirmed
    assert by_edge[{:monthly_tasks_generated, :accounting_month_opened}].state == :confirmed

    # The divergence path was not traversed — and that is exactly the information
    # this view exists for.
    assert by_edge[{:registry_discrepancy_detected, :discrepancy_notification_sent}].state == :dead
  end

  test "volume is a dimension separate from state" do
    for period <- ["2026-05", "2026-06", "2026-07"] do
      {:ok, _} = Taxvision.Api.open_month(accountant("c-1"), %{company_id: "c-1", period: period})
    end

    overlay = PNS.Graph.overlay()
    edge = Enum.find(overlay, &(&1.to == :accounting_month_opened))

    assert edge.state == :confirmed
    assert edge.count == 3
  end

  test "the events of the later stages are declared and never observed" do
    {:ok, _} = Taxvision.Api.open_month(accountant("c-1"), %{company_id: "c-1", period: "2026-07"})

    dead = PNS.Graph.declared_never_observed() |> Enum.map(& &1.event)

    assert :bank_statement_received in dead
    assert :turnover_matched_with_invoice in dead
    assert :month_closed in dead

    refute :accounting_month_opened in dead
    refute :monthly_tasks_generated in dead
  end

  test "cadence is what the window is computed from — and it is declared" do
    [entry] = PNS.Graph.declared_never_observed() |> Enum.filter(&(&1.event == :month_closed))

    assert entry.process == :accounting_month
    assert entry.cadence == {1, :month}
  end

  test "an event under a different contract version is history, not drift" do
    {:ok, _} = Taxvision.Api.open_month(accountant("c-1"), %{company_id: "c-1", period: "2026-07"})

    # Simulating a deploy that removed an event: a row in the log under a contract
    # version that is no longer in the binary.
    Repo.insert!(%PNS.Event{
      type: "event_from_last_month",
      contract: inspect(AccountingMonth),
      contract_version: "version_that_is_gone",
      correlation_id: Ecto.UUID.generate(),
      causation_id: List.first(events_of(:accounting_month_opened)).id,
      payload: %{},
      occurred_at: DateTime.utc_now()
    })

    overlay = PNS.Graph.overlay()
    entry = Enum.find(overlay, &(&1.to == "event_from_last_month"))

    assert entry.state == :historical,
           "without `contract_version` every deploy that removes an event produces false drift"
  end

  test "a job waiting in the queue is :in_flight, not :dead" do
    Application.put_env(:pns_prototype, Taxvision.Adapters.RegistryLookup.Fake,
      responses: %{"c-1" => {:ok, %{legal_form: "JDG", vat_status: "wykreślony", vies_status: "aktywny"}}}
    )

    on_exit(fn -> Application.delete_env(:pns_prototype, Taxvision.Adapters.RegistryLookup.Fake) end)

    {:ok, _} = Taxvision.Api.open_month(accountant("c-1"), %{company_id: "c-1", period: "2026-07"})

    # The job is inserted and not run — exactly the moment at which a dashboard
    # without the third state would claim the path never works.
    edge =
      PNS.Graph.overlay()
      |> Enum.find(&(&1.to == :discrepancy_notification_sent))

    assert edge.state == :in_flight
    assert edge.count == 0
    assert edge.in_flight == 1
  end

  test "events from one command are siblings, not a chain" do
    {:ok, _} = Taxvision.Api.open_month(accountant("c-1"), %{company_id: "c-1", period: "2026-07"})

    siblings = PNS.Graph.command_siblings()

    # The three opening events plus the check's result: no cause, a shared
    # correlation. None of them caused another.
    assert siblings[{"data_completeness_confirmed", "registry_status_checked"}] == 1
    assert siblings[{"registry_status_checked", "registry_check_logged"}] == 1

    # And this is real causation, which must not end up among the siblings.
    refute Map.has_key?(siblings, {"registry_data_consistent", "monthly_tasks_generated"})
  end

  test "mermaid comes out of the overlay, not out of a separate file" do
    {:ok, _} = Taxvision.Api.open_month(accountant("c-1"), %{company_id: "c-1", period: "2026-07"})

    mermaid = PNS.Graph.overlay() |> PNS.Graph.to_mermaid()

    assert mermaid =~ "flowchart LR"
    assert mermaid =~ "registry_data_consistent"
    assert mermaid =~ "classDef confirmed"
    assert mermaid =~ "month_closed[\""
    assert mermaid =~ "-.->|" and mermaid =~ "async"
    assert mermaid =~ "same command"
  end
end
