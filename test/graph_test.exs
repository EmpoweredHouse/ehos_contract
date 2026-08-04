defmodule PNS.GraphTest do
  @moduledoc """
  Czy z kontraktu da się zrobić graf i czy nakładka na log ma sens.

  To jest pytanie „czy to ma szanse" postawione jako test, a nie jako opinia.
  Dashboardu nie ma i celowo nie będzie w tym kroku — najpierw sprawdzić, czy
  różnica jest sygnałem.
  """

  use Taxvision.DataCase, async: false

  alias Taxvision.Contracts.AccountingMonth

  test "graf statyczny pochodzi z rejestru, czyli z binarki" do
    graph = PNS.Graph.static()

    assert length(graph.nodes) == length(AccountingMonth.events())

    edges = MapSet.new(graph.edges, &{&1.from, &1.to})
    assert MapSet.member?(edges, {:registry_data_consistent, :monthly_tasks_generated})
    assert MapSet.member?(edges, {:monthly_tasks_generated, :accounting_month_opened})
    assert MapSet.member?(edges, {:registry_discrepancy_detected, :discrepancy_notification_sent})

    async = Enum.filter(graph.edges, & &1.async)
    assert Enum.map(async, & &1.from) == [:registry_discrepancy_detected]
  end

  test "przed jakimkolwiek przebiegiem wszystko jest martwe, nic nie jest driftem" do
    overlay = PNS.Graph.overlay()

    assert Enum.all?(overlay, &(&1.state == :dead))
    assert Enum.all?(overlay, &(&1.count == 0))
  end

  test "po przebiegu krawędzie przechodzą w confirmed, a niewykonane zostają martwe" do
    {:ok, _} = Taxvision.Api.open_month(accountant("c-1"), %{company_id: "c-1", period: "2026-07"})

    overlay = PNS.Graph.overlay()
    by_edge = Map.new(overlay, &{{&1.from, &1.to}, &1})

    assert by_edge[{:registry_data_consistent, :monthly_tasks_generated}].state == :confirmed
    assert by_edge[{:monthly_tasks_generated, :accounting_month_opened}].state == :confirmed

    # Ścieżka rozjazdu nie została przejechana — i to jest właśnie ta
    # informacja, po którą się tu przychodzi.
    assert by_edge[{:registry_discrepancy_detected, :discrepancy_notification_sent}].state == :dead
  end

  test "wolumen jest wymiarem osobnym od stanu" do
    for period <- ["2026-05", "2026-06", "2026-07"] do
      {:ok, _} = Taxvision.Api.open_month(accountant("c-1"), %{company_id: "c-1", period: period})
    end

    overlay = PNS.Graph.overlay()
    edge = Enum.find(overlay, &(&1.to == :accounting_month_opened))

    assert edge.state == :confirmed
    assert edge.count == 3
  end

  test "zdarzenia faz 3.2-3.4 są zadeklarowane i nigdy nie zaobserwowane" do
    {:ok, _} = Taxvision.Api.open_month(accountant("c-1"), %{company_id: "c-1", period: "2026-07"})

    dead = PNS.Graph.declared_never_observed() |> Enum.map(& &1.event)

    assert :bank_statement_received in dead
    assert :turnover_matched_with_invoice in dead
    assert :month_closed in dead

    refute :accounting_month_opened in dead
    refute :monthly_tasks_generated in dead
  end

  test "cadence jest tym, z czego liczy się okno — i jest zadeklarowana" do
    [entry] = PNS.Graph.declared_never_observed() |> Enum.filter(&(&1.event == :month_closed))

    assert entry.process == :accounting_month
    assert entry.cadence == {1, :month}
  end

  test "zdarzenie pod inną wersją kontraktu to historia, nie drift" do
    {:ok, _} = Taxvision.Api.open_month(accountant("c-1"), %{company_id: "c-1", period: "2026-07"})

    # Symulacja deployu, który usunął zdarzenie: wiersz w logu pod wersją
    # kontraktu, której już nie ma w binarce.
    Repo.insert!(%PNS.Event{
      type: "zdarzenie_z_zeszlego_miesiaca",
      contract: inspect(AccountingMonth),
      contract_version: "wersja_ktorej_juz_nie_ma",
      correlation_id: Ecto.UUID.generate(),
      causation_id: List.first(events_of(:accounting_month_opened)).id,
      payload: %{},
      occurred_at: DateTime.utc_now()
    })

    overlay = PNS.Graph.overlay()
    entry = Enum.find(overlay, &(&1.to == "zdarzenie_z_zeszlego_miesiaca"))

    assert entry.state == :historical,
           "bez `contract_version` każdy deploy usuwający zdarzenie produkuje fałszywy drift"
  end

  test "mermaid wychodzi z nakładki, nie z osobnego pliku" do
    {:ok, _} = Taxvision.Api.open_month(accountant("c-1"), %{company_id: "c-1", period: "2026-07"})

    mermaid = PNS.Graph.overlay() |> PNS.Graph.to_mermaid()

    assert mermaid =~ "flowchart LR"
    assert mermaid =~ "registry_data_consistent"
    assert mermaid =~ "classDef confirmed"
    assert mermaid =~ "month_closed[\""
    assert mermaid =~ "-.->|" and mermaid =~ "async"
  end
end
