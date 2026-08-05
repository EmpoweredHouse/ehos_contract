defmodule PNS.ConformanceTest do
  @moduledoc """
  Etap 1.4: **behawioralna weryfikacja ścieżek, per przebieg.**

  Kryterium odbioru jest ostre i jest pierwszym blokiem poniżej: przy 50
  przebiegach, z których żaden nie wszedł w gałąź blokującą, raport pokazuje
  **jedną** nieprzejechaną ścieżkę. Przy jednym przebiegu w tę gałąź — **zero**.

  To jest jednocześnie test na to, czy różnica declared vs observed jest
  sygnałem, czy szumem — czyli warunek falsyfikacji z ADR-a. Pięćdziesiąt
  przebiegów, jedna linia raportu. Gdyby raport pokazał pięćdziesiąt albo trzy,
  odpowiedź brzmiałaby „szum".

  Wolumen jest symulowany, ale **proces nie**: przebiegi idą przez istniejący
  kontrakt z warsztatu TaxVision, a nie przez fazy dopisane pod ten test.
  Kontrakt zaprojektowany pod własne kryterium odbioru zawsze je spełni.
  """

  use Taxvision.DataCase, async: false
  use Oban.Testing, repo: Taxvision.Repo

  @rozjazd %{legal_form: "JDG", vat_status: "wykreślony", vies_status: "aktywny"}
  @blokada {:registry_discrepancy_detected, :discrepancy_notification_sent}

  defp rejestry(mapa) do
    Application.put_env(:pns_prototype, Taxvision.Adapters.RegistryLookup.Fake, responses: mapa)
    on_exit(fn -> Application.delete_env(:pns_prototype, Taxvision.Adapters.RegistryLookup.Fake) end)
  end

  defp otworz(firma) do
    {:ok, _} = Taxvision.Api.open_month(accountant(firma), %{company_id: firma, period: "2026-07"})
  end

  defp raport do
    [r] = PNS.Conformance.untraversed_paths() |> Enum.filter(&(&1.process == :accounting_month))
    r
  end

  defp sciezki(raport), do: Enum.map(raport.untraversed, &{&1.from, &1.to})

  describe "kryterium odbioru" do
    test "50 przebiegów, żaden w gałęzi blokującej — dokładnie jedna nieprzejechana ścieżka" do
      for n <- 1..50, do: otworz("c-#{n}")

      r = raport()

      assert r.instances == 50
      assert r.basis == :runs
      assert sciezki(r) == [@blokada]

      # Sedno: raport ma **jedną** linię, nie pięćdziesiąt i nie trzy. Gdyby
      # liczył per typ zdarzenia, ta jedna ścieżka i tak by wyszła — ale przy
      # 49 zgodnych i jednym rozjeździe (test niżej) już nie.
      assert length(r.untraversed) == 1
    end

    test "jeden przebieg w gałąź blokującą — zero nieprzejechanych ścieżek" do
      rejestry(%{"c-50" => {:ok, @rozjazd}})

      for n <- 1..50, do: otworz("c-#{n}")
      # Powiadomienie idzie handlerem asynchronicznym, więc ścieżka domyka się
      # dopiero po wykonaniu joba.
      Oban.drain_queue(queue: :events)

      r = raport()

      assert r.instances == 50
      assert r.untraversed == []
      assert r.in_flight == []
    end
  end

  describe "dwie sytuacje, w których raport łatwo skłamie" do
    test "zero przebiegów to brak podstawy, nie trzy znaleziska" do
      r = raport()

      assert r.instances == 0
      assert r.basis == :no_runs

      assert r.untraversed == [],
             "proces, który nigdy nie ruszył, ma wszystkie ścieżki nieprzejechane — " <>
               "wypisanie ich zamienia „nie ma danych” w „mamy trzy problemy”"

      assert r.paths == 3
    end

    test "job czekający w kolejce nie jest nieprzejechaną ścieżką" do
      rejestry(%{"c-1" => {:ok, @rozjazd}})
      otworz("c-1")

      r = raport()

      refute @blokada in sciezki(r),
             "job w kolejce to „jeszcze nie”, nie „nigdy” — bez tego raport kłamie " <>
               "przy każdym normalnym opóźnieniu"

      assert Enum.map(r.in_flight, &{&1.from, &1.to}) == [@blokada]
    end
  end

  describe "kształt raportu" do
    test "ścieżki niezadeklarowane nie trafiają do tej listy" do
      # Drift jest innym pytaniem ekranu. Zmieszany w jednej liście robi z
      # raportu worek, w którym nie da się odróżnić „nie zrobiliśmy" od
      # „zrobiliśmy coś, czego nie ustaliliśmy".
      otworz("c-1")

      Repo.insert!(%PNS.Event{
        type: "zdarzenie_spoza_kontraktu",
        contract: inspect(Taxvision.Contracts.AccountingMonth),
        contract_version: Taxvision.Contracts.AccountingMonth.version(),
        correlation_id: Ecto.UUID.generate(),
        causation_id: List.first(events_of(:accounting_month_opened)).id,
        payload: %{},
        occurred_at: DateTime.utc_now()
      })

      assert Enum.all?(raport().untraversed, & &1.handler)
    end

    test "raport per proces, a nie jedna globalna lista" do
      # Notatki §9: „navigation is per-process, never global".
      otworz("c-1")

      procesy = PNS.Conformance.untraversed_paths() |> Enum.map(& &1.process)
      assert :accounting_month in procesy
    end
  end
end
