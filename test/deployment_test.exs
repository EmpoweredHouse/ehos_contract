defmodule PNS.DeploymentTest do
  @moduledoc """
  Etap 1.6: **wersja kontraktu jako pierwszoklasowa odpowiedź.**

  Kryterium odbioru ma trzy części i najostrzejsza jest ostatnia: raport mówi,
  które ścieżki są nowe, które zniknęły, które zdarzenia pochodzą z poprzedniej
  wersji — i **bez ani jednego fałszywego driftu**.

  Pierwszy blok poniżej jest odtworzeniem fałszywego driftu, który tu był, żeby
  poprawka nie okazała się poprawką na coś, czego nie było.
  """

  use Taxvision.DataCase, async: false

  alias Taxvision.Contracts.AccountingMonth, as: Umowa

  @okres "2026-07"

  defp otworz(firma) do
    {:ok, _} = Taxvision.Api.open_month(accountant(firma), %{company_id: firma, period: @okres})
  end

  defp wdrozenie(atrybuty) do
    Repo.insert!(
      struct(
        %PNS.Deployment{
          contract: inspect(Umowa),
          contract_version: Umowa.version(),
          wiring_version: "wiring-old",
          events: Umowa.event_names() |> Enum.map(&to_string/1) |> Enum.sort(),
          edges: [],
          first_seen_at: DateTime.utc_now()
        },
        atrybuty
      )
    )
  end

  describe "fałszywy drift, którego kryterium odbioru zabrania" do
    test "usunięcie handlera nie zmienia żadnej wersji — a jednak zmienia graf" do
      # To jest przyczyna, nie objaw. `version/0` haszuje deklaracje kontraktu;
      # ścieżki pochodzą z `publishes:` handlerów, których w tym haszu nie ma.
      przed = Umowa.version()
      krawedzie = PNS.Registry.edges() |> Enum.map(&{&1.from, &1.to})

      assert {:registry_data_consistent, :monthly_tasks_generated} in krawedzie
      assert Umowa.version() == przed, "kontrakt się nie zmienił"

      # Czyli: gdyby ktoś usunął handler, `contract_version` w logu zostałby ten
      # sam, a krawędź przestałaby być zadeklarowana.
    end

    test "krawędź zadeklarowana w zapisanym wdrożeniu to historia, nie drift" do
      otworz("c-1")

      # Wdrożenie, w którym ta krawędź **była** zadeklarowana, a dziś jej nie ma
      # w rejestrze — dokładnie sytuacja po usunięciu handlera.
      wdrozenie(%{wiring_version: "wiring-1", edges: ["accounting_month_opened->month_closed"]})

      Repo.insert!(%PNS.Event{
        type: "month_closed",
        contract: inspect(Umowa),
        contract_version: Umowa.version(),
        process: "accounting_month",
        instance_id: "accounting_month|c-1|#{@okres}",
        correlation_id: Ecto.UUID.generate(),
        causation_id: List.first(events_of(:accounting_month_opened)).id,
        payload: %{},
        occurred_at: DateTime.utc_now()
      })

      wpis =
        PNS.Graph.overlay()
        |> Enum.find(&(&1.from == "accounting_month_opened" and &1.to == "month_closed"))

      assert wpis.state == :historical,
             "krawędź była zadeklarowana, kiedy przejechała — obwinianie jej o drift " <>
               "to fałszywy alarm, którego kryterium 1.6 zabrania"
    end

    test "krawędź, której nigdy nie zadeklarowano, nadal jest driftem" do
      # Poprawka nie ma prawa uciszyć prawdziwego driftu.
      otworz("c-1")

      Repo.insert!(%PNS.Event{
        type: "nigdy_nie_zadeklarowane",
        contract: inspect(Umowa),
        contract_version: Umowa.version(),
        correlation_id: Ecto.UUID.generate(),
        causation_id: List.first(events_of(:accounting_month_opened)).id,
        payload: %{},
        occurred_at: DateTime.utc_now()
      })

      wpis = PNS.Graph.overlay() |> Enum.find(&(&1.to == "nigdy_nie_zadeklarowane"))

      assert wpis.state == :drift
    end
  end

  describe "dwie tożsamości wdrożenia" do
    test "wersja kontraktu i wersja obwodowania są osobne i osobno się ruszają" do
      PNS.Deployment.record!()
      [wdrozone] = PNS.Deployment.all(Umowa)

      assert wdrozone.contract_version == Umowa.version()
      assert wdrozone.wiring_version != wdrozone.contract_version

      # Obwodowanie zna ścieżki, kontrakt ich nie zna.
      assert "registry_data_consistent->monthly_tasks_generated" in wdrozone.edges
      refute Enum.empty?(wdrozone.events)
    end

    test "ten sam kod zapisany dwa razy to jedno wdrożenie" do
      PNS.Deployment.record!()
      PNS.Deployment.record!()

      assert length(PNS.Deployment.all(Umowa)) == 1
    end

    test "hash obwodowania jest kanoniczny — z posortowanych stringów, nie z termu" do
      # `version/0` liczy hash przez `term_to_binary`, więc aktualizacja OTP może
      # przekwalifikować całą historię (luka 2.4). Tutaj tego problemu nie ma i
      # to jest wzór dla tamtej poprawki.
      PNS.Deployment.record!()
      [a] = PNS.Deployment.all(Umowa)

      Repo.delete_all(PNS.Deployment)
      PNS.Deployment.record!()
      [b] = PNS.Deployment.all(Umowa)

      assert a.wiring_version == b.wiring_version
    end
  end

  describe "raport: co wdrożone, od kiedy, co się zmieniło" do
    test "od kiedy to pierwsze zdarzenie pod tą wersją, nie moment deployu" do
      PNS.Deployment.record!()
      otworz("c-1")

      raport = PNS.Deployment.report(Umowa)
      pierwsze = List.first(events_of(:data_completeness_confirmed))

      assert raport.deployed.contract_version == Umowa.version()
      assert raport.deployed.since == pierwsze.occurred_at
    end

    test "wdrożenie, które nic jeszcze nie wyemitowało, ma `since: nil`" do
      # Wdrożone i niedowiedzione. `nil` jest tu uczciwsze niż data deployu,
      # której silnik nie zna.
      PNS.Deployment.record!()

      assert PNS.Deployment.report(Umowa).deployed.since == nil
    end

    test "wersje w logu z licznikami i zakresami" do
      otworz("c-1")

      Repo.insert!(%PNS.Event{
        type: "data_completeness_confirmed",
        contract: inspect(Umowa),
        contract_version: "stara-wersja",
        correlation_id: Ecto.UUID.generate(),
        payload: %{},
        occurred_at: ~U[2026-06-01 09:00:00.000000Z]
      })

      raport = PNS.Deployment.report(Umowa)
      wersje = Map.new(raport.in_log, &{&1.contract_version, &1})

      assert wersje["stara-wersja"].events == 1
      assert wersje["stara-wersja"].first_at == ~U[2026-06-01 09:00:00.000000Z]
      assert wersje[Umowa.version()].events > 1

      # Ile zdarzeń pochodzi z wersji innej niż wdrożona — wprost, bez liczenia
      # przez czytelnika.
      assert raport.from_earlier_versions == 1
    end

    test "diff mówi osobno o zdarzeniach i osobno o ścieżkach" do
      # Ruszają się niezależnie: handler może dodać ścieżkę bez zmiany kontraktu.
      wdrozenie(%{
        wiring_version: "wiring-1",
        events: ["a", "b"],
        edges: ["a->b"],
        first_seen_at: ~U[2026-08-01 09:00:00.000000Z]
      })

      wdrozenie(%{
        contract_version: "nowa",
        wiring_version: "wiring-2",
        events: ["a", "c"],
        edges: ["a->b", "a->c"],
        first_seen_at: ~U[2026-08-02 09:00:00.000000Z]
      })

      zmiana = PNS.Deployment.report(Umowa).changed

      assert zmiana.events_added == ["c"]
      assert zmiana.events_removed == ["b"]
      assert zmiana.paths_added == ["a->c"]
      assert zmiana.paths_removed == []
    end

    test "jedno wdrożenie to brak zmiany, nie zmiana pusta" do
      PNS.Deployment.record!()
      assert PNS.Deployment.report(Umowa).changed == nil
    end
  end
end
