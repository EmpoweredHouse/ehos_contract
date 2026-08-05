defmodule PNS.TraceTest do
  @moduledoc """
  Etap 1.5: **ocena assercji `trace` per przebieg.**

  Kryterium odbioru jest jedno i jest pierwszym testem poniżej: przy
  zablokowanym miesiącu assercja jest **spełniona przez `or_else`**, nie
  naruszona. Blokada to poprawne zakończenie, tylko nie takie, jak chcieliśmy —
  a narzędzie, które krzyczy na każdy poprawnie zablokowany miesiąc, zostanie
  wyłączone w tydzień.

  Reszta testów pinuje decyzje semantyczne, z których każda daje się zepsuć w
  drugą stronę bez łamania czegokolwiek innego.
  """

  use Taxvision.DataCase, async: false
  use Oban.Testing, repo: Taxvision.Repo

  alias Taxvision.Contracts.AccountingMonth, as: Umowa

  @assercja :month_opens_or_is_blocked
  @zgodne %{legal_form: "JDG", vat_status: "czynny", vies_status: "aktywny"}
  @rozjazd %{legal_form: "JDG", vat_status: "wykreślony", vies_status: "aktywny"}

  defp rejestry(mapa) do
    Application.put_env(:pns_prototype, Taxvision.Adapters.RegistryLookup.Fake, responses: mapa)
    on_exit(fn -> Application.delete_env(:pns_prototype, Taxvision.Adapters.RegistryLookup.Fake) end)
  end

  defp otworz(firma, okres \\ "2026-07") do
    {:ok, _} = Taxvision.Api.open_month(accountant(firma), %{company_id: firma, period: okres})
  end

  # Powiadomienie o rozjeździe wychodzi handlerem **asynchronicznym**, więc
  # `or_else` nie istnieje w logu, dopóki job nie ruszy. W testach joby stoją
  # (`testing: :manual`), co jest tu zaletą: pozwala oddzielić „umowa dotrzymana"
  # od „umowa dopiero będzie dotrzymana".
  defp wykonaj_joby, do: Oban.drain_queue(queue: :events)

  defp ocen(opts \\ []), do: PNS.Trace.evaluate(Umowa, @assercja, opts)
  defp instancja(firma, okres \\ "2026-07"), do: "accounting_month|#{firma}|#{okres}"

  describe "kryterium odbioru" do
    test "zablokowany miesiąc jest SPEŁNIONY przez or_else, nie naruszony" do
      rejestry(%{"c-1" => {:ok, @rozjazd}})
      otworz("c-1")
      wykonaj_joby()

      assert [w] = ocen()

      assert w.verdict == :satisfied,
             "blokada na rozjeździe jest poprawnym zakończeniem procesu, nie naruszeniem umowy"

      assert w.via == :or_else
      assert w.instance_id == instancja("c-1")
    end

    test "otwarty miesiąc jest spełniony przez eventually" do
      rejestry(%{"c-1" => {:ok, @zgodne}})
      otworz("c-1")

      assert [w] = ocen()
      assert w.verdict == :satisfied
      assert w.via == :eventually
    end

    test "dwa przebiegi, dwa różne sposoby spełnienia — i nie mieszają się" do
      # To jest 1.1 i 1.5 spięte razem: bez tożsamości przebiegu ta assercja
      # policzyłaby się raz, globalnie, i zaliczyłaby oba przebiegi tak samo.
      rejestry(%{"c-1" => {:ok, @zgodne}, "c-2" => {:ok, @rozjazd}})
      otworz("c-1")
      otworz("c-2")
      wykonaj_joby()

      po_instancji = Map.new(ocen(), &{&1.instance_id, &1})

      assert po_instancji[instancja("c-1")].via == :eventually
      assert po_instancji[instancja("c-2")].via == :or_else

      assert PNS.Trace.summary(ocen()) == %{
               satisfied: 2,
               satisfied_via_eventually: 1,
               satisfied_via_or_else: 1,
               violated: 0,
               pending: 0,
               instances: 2
             }
    end
  end

  describe "wyjście za granicą procesu BEAM-a" do
    test "dopóki job z `or_else` stoi w kolejce, werdykt jest `pending`" do
      # To jest ta sama lekcja, co czwarty stan nakładki: „jeszcze nie" wygląda
      # w logu identycznie jak „nigdy". Decyzja o blokadzie już zapadła, ale
      # powiadomienie jeszcze nie poszło, więc umowa nie jest **jeszcze**
      # dotrzymana — i werdykt nie ma prawa twierdzić, że jest.
      rejestry(%{"c-1" => {:ok, @rozjazd}})
      otworz("c-1")

      assert [w] = ocen()
      assert w.verdict == :pending

      # A po wykonaniu joba ta sama assercja jest spełniona. Koszt asynchronii
      # jest nazwany: job zaklinowany na dłużej niż okno policzy się jako
      # naruszenie — poprawnie, bo powiadomienie faktycznie nie poszło.
      wykonaj_joby()
      assert [%{verdict: :satisfied, via: :or_else}] = ocen()
    end
  end

  describe "okno" do
    # Zdarzenia wstawiane wprost, bo tylko tak da się ustawić `occurred_at`.
    defp fakt(typ, firma, at, okres \\ "2026-07") do
      Repo.insert!(%PNS.Event{
        type: to_string(typ),
        contract: inspect(Umowa),
        contract_version: Umowa.version(),
        process: "accounting_month",
        instance_id: instancja(firma, okres),
        correlation_id: Ecto.UUID.generate(),
        payload: %{"company_id" => firma, "period" => okres},
        occurred_at: at
      })
    end

    @start ~U[2026-07-01 09:00:00.000000Z]

    test "przed upływem okna werdykt jest `pending`, nie `violated`" do
      fakt(:data_completeness_confirmed, "c-1", @start)

      assert [w] = ocen(now: DateTime.add(@start, 1, :day))
      assert w.verdict == :pending
      assert w.deadline_at == DateTime.add(@start, 2, :day)
    end

    test "po upływie okna, bez żadnego z dwóch wyjść, werdykt jest `violated`" do
      fakt(:data_completeness_confirmed, "c-1", @start)

      assert [w] = ocen(now: DateTime.add(@start, 3, :day))
      assert w.verdict == :violated
      assert w.via == nil
    end

    test "wyjście po terminie nie ratuje assercji" do
      fakt(:data_completeness_confirmed, "c-1", @start)
      fakt(:accounting_month_opened, "c-1", DateTime.add(@start, 5, :day))

      assert [w] = ocen(now: DateTime.add(@start, 6, :day))
      assert w.verdict == :violated
    end

    test "ponowne `from` NIE przesuwa terminu" do
      # Gdyby okno liczyło się od ostatniego wystąpienia, proces uciekałby przed
      # terminem w nieskończoność, po prostu emitując `from` ponownie — i tej
      # assercji nie dałoby się nigdy naruszyć.
      fakt(:data_completeness_confirmed, "c-1", @start)
      fakt(:data_completeness_confirmed, "c-1", DateTime.add(@start, 10, :day))

      assert [w] = ocen(now: DateTime.add(@start, 11, :day))
      assert w.verdict == :violated
      assert w.from_at == @start
    end

    test "`or_else` też podlega terminowi" do
      # Decyzja do potwierdzenia przez process ownera: „w ciągu dwóch dni X albo
      # Y" znaczy, że oba mają się zmieścić. Inaczej termin jest bezużyteczny.
      fakt(:data_completeness_confirmed, "c-1", @start)
      fakt(:discrepancy_notification_sent, "c-1", DateTime.add(@start, 4, :day))

      assert [w] = ocen(now: DateTime.add(@start, 5, :day))
      assert w.verdict == :violated
    end
  end

  describe "assercja jest warunkowa" do
    test "przebieg bez `from` nie jest oceniany wcale" do
      # Nie jest ani spełniony, ani naruszony — nie ma o czym orzekać. Liczenie
      # go jako naruszenia zrobiłoby alarm z każdej niezaczętej sprawy.
      fakt(:accounting_month_opened, "c-9", @start)

      assert ocen(now: DateTime.add(@start, 30, :day)) == []
    end

    test "pusty log to zero werdyktów, nie zero naruszeń" do
      assert ocen() == []
      assert PNS.Trace.summary(ocen()).instances == 0
    end
  end

  describe "wszystkie kontrakty" do
    test "assercje drugiej domeny są oceniane tym samym kodem" do
      rejestry(%{"c-1" => {:ok, @zgodne}})
      otworz("c-1")

      wszystkie = PNS.Trace.evaluate_all()
      nazwy = Enum.map(wszystkie, & &1.trace) |> Enum.sort()

      assert nazwy == [:episode_reaches_an_end, :month_opens_or_is_blocked, :referral_reaches_a_decision]

      # Kontrakt medyczny nie ma implementacji, więc jego assercje nie mają
      # przebiegów do oceny — i to jest zero werdyktów, nie zero naruszeń.
      medyczne = Enum.filter(wszystkie, &(&1.contract == UniversalityGate.TreatmentEpisode))
      assert Enum.all?(medyczne, &(&1.verdicts == []))
    end
  end
end
