defmodule Taxvision.ReportTest do
  @moduledoc """
  Etap 1.7: **raport zgodności za okres.**

  Kryterium odbioru ma dwie części i druga jest twarda:

  1. czytelny bez tłumaczenia, co znaczą kolumny,
  2. **nie zawiera `deadline` oznaczonego `unverified`.**

  Druga jest mierzalna i jest pierwszym blokiem poniżej. Pierwsza jest z natury
  miękka, ale da się przypiąć od strony przeciwnej: w raporcie nie ma ani jednej
  nazwy technicznej zdarzenia, bo każda jest zastąpiona etykietą z kontraktu.
  """

  use Taxvision.DataCase, async: false
  use Oban.Testing, repo: Taxvision.Repo

  alias Taxvision.Contracts.AccountingMonth, as: Umowa

  @zgodne %{legal_form: "JDG", vat_status: "czynny", vies_status: "aktywny"}
  @rozjazd %{legal_form: "JDG", vat_status: "wykreślony", vies_status: "aktywny"}

  defp rejestry(mapa) do
    Application.put_env(:pns_prototype, Taxvision.Adapters.RegistryLookup.Fake, responses: mapa)
    on_exit(fn -> Application.delete_env(:pns_prototype, Taxvision.Adapters.RegistryLookup.Fake) end)
  end

  defp otworz(firma, okres \\ "2026-07") do
    {:ok, _} = Taxvision.Api.open_month(accountant(firma), %{company_id: firma, period: okres})
  end

  defp dane(opts \\ []), do: PNS.Conformance.report(Umowa, opts)
  defp tekst(opts \\ []), do: opts |> dane() |> Taxvision.Report.render()

  describe "kryterium odbioru: bez niepotwierdzonych deklaracji" do
    test "termin oznaczony `unverified` nie trafia do danych raportu" do
      # `deadline: {25, :day}` jest w kontrakcie z `unverified: [:deadline]`, bo
      # liczba jest prawdopodobna, ale **nikt z TaxVision jej nie podał**.
      assert :deadline in Umowa.process(:accounting_month).unverified

      [proces] = dane().processes
      klucze = Enum.map(proces.declarations, & &1.key)

      refute :deadline in klucze,
             "niepotwierdzona deklaracja w raporcie dowodowym czyta się jako zmierzona — " <>
               "a fałszywa metryka jest gorsza niż jej brak, bo to metryka, którą produkt sprzedaje"

      # Kadencja jest potwierdzona warsztatem [WF 00:34:40], więc zostaje.
      assert :cadence in klucze
    end

    test "termin nie trafia też do wyrenderowanego tekstu" do
      refute tekst() =~ "Termin"
      refute tekst() =~ "25"
    end

    test "gdyby termin został potwierdzony, pojawiłby się" do
      # Dowód, że filtr działa na `unverified`, a nie po prostu nie umie wypisać
      # terminu. Bez tego pierwszy test przechodziłby także przy zepsutym filtrze.
      proces = Umowa.process(:accounting_month)
      potwierdzony = %{proces | unverified: []}

      refute Enum.any?(PNS.Conformance.verified_declarations(proces), &(&1.key == :deadline))
      assert Enum.any?(PNS.Conformance.verified_declarations(potwierdzony), &(&1.key == :deadline))
    end
  end

  describe "kryterium odbioru: czytelny bez tłumaczenia" do
    setup do
      rejestry(%{"c-1" => {:ok, @zgodne}, "c-2" => {:ok, @rozjazd}})
      otworz("c-1")
      otworz("c-2")
      Oban.drain_queue(queue: :events)
      :ok
    end

    test "kroki są nazwane etykietami biznesowymi, nie nazwami zdarzeń" do
      t = tekst()

      # Assercja jest zdaniem złożonym z etykiet, bo `trace` nie ma `label`.
      assert t =~ "po „Potwierdzono komplet danych historycznych”"
      assert t =~ "następuje „Otwarto miesiąc księgowy”"

      refute t =~ "data_completeness_confirmed"
      refute t =~ "accounting_month_opened"
    end

    test "spełnienie przez ścieżkę awaryjną jest nazwane zgodnością, nie wyjątkiem" do
      # Blokada miesiąca jest poprawnym zakończeniem. Raport, który nazwałby ją
      # problemem, zostałby wyłączony po pierwszym miesiącu.
      assert tekst() =~ "Dotrzymane we wszystkich 2 przebiegach"
      assert tekst() =~ "zgodne z ustaleniem"
    end

    test "cztery pytania ekranu są w jednym artefakcie" do
      t = tekst()

      assert t =~ "USTALENIA"
      assert t =~ "Wersja ustaleń"
      assert t =~ "PROCES"
      assert t =~ "Ustalenie: po"
      assert t =~ "ROZBIEŻNOŚCI"
    end

    test "brak rozbieżności jest zdaniem, nie pustą sekcją" do
      assert tekst() =~ "Brak: nic nie zaszło poza ustaleniami"
    end
  end

  describe "raport jest za okres" do
    test "okno odcina przebiegi spoza okresu" do
      otworz("c-1", "2026-06")
      otworz("c-2", "2026-07")

      wszystko = dane()
      lipiec = dane(since: ~U[2026-08-05 00:00:00.000000Z])

      [p_wszystko] = wszystko.processes
      [p_lipiec] = lipiec.processes

      assert p_wszystko.runs == 2
      assert p_lipiec.runs == 2

      # Okno w przyszłości nie może zawierać niczego — dowód, że granica działa,
      # a nie że jest ignorowana.
      pusty = dane(since: ~U[2027-01-01 00:00:00.000000Z])
      [p_pusty] = pusty.processes

      assert p_pusty.runs == 0
    end

    test "okres bez przebiegów mówi „nie ma czego oceniać”, nie „wszystko dobrze”" do
      otworz("c-1")

      t = tekst(since: ~U[2027-01-01 00:00:00.000000Z])

      assert t =~ "nie było ani jednego przebiegu"
      refute t =~ "Wszystkie ustalone kroki zostały"
    end

    test "nagłówek nazywa okres, którego raport dotyczy" do
      t = tekst(since: ~U[2026-07-01 00:00:00.000000Z], until: ~U[2026-07-31 23:59:59.000000Z])
      assert t =~ "2026-07-01 – 2026-07-31"
    end
  end

  describe "rozbieżność jest przypisana do właściwego kontraktu" do
    test "drift wchodzi do raportu tego kontraktu, którego zdarzenie go wywołało" do
      otworz("c-1")

      Repo.insert!(%PNS.Event{
        type: "zdarzenie_spoza_ustalen",
        contract: inspect(Umowa),
        contract_version: Umowa.version(),
        correlation_id: Ecto.UUID.generate(),
        causation_id: List.first(events_of(:accounting_month_opened)).id,
        payload: %{},
        occurred_at: DateTime.utc_now()
      })

      assert [rozbieznosc] = dane().drift
      assert rozbieznosc.to == "zdarzenie_spoza_ustalen"
      assert rozbieznosc.from_label == "Otwarto miesiąc księgowy"

      # Raport innego kontraktu nie ma prawa tego zobaczyć.
      assert PNS.Conformance.report(UniversalityGate.TreatmentEpisode).drift == []
    end
  end
end
