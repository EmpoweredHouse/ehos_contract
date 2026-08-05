defmodule PNS.UniversalityGateTest do
  @moduledoc """
  Etap 1.2: **brama uniwersalności.**

  Do tej pory dowód na to, że DSL nie jest księgowy, brzmiał „jeden kontrakt,
  jedna domena, jeden autor" — czyli nie był dowodem. `UniversalityGate.
  TreatmentEpisode` jest drugim kontraktem z domeny, która z księgowością nie ma
  nic wspólnego, i jest **świadomie wymyślony** (patrz jego moduledoc).

  Kryterium odbioru jest twarde: **zero nowych słów w DSL.** Pierwszy test
  poniżej pinuje słownik, więc kryterium jest sprawdzane, a nie deklarowane.
  """

  use ExUnit.Case, async: true

  @contract UniversalityGate.TreatmentEpisode
  @taxvision Taxvision.Contracts.AccountingMonth

  describe "kryterium odbioru: zero nowych słów" do
    test "słownik DSL nie urósł, żeby zmieścić drugą domenę" do
      # Ten test jest całym kryterium etapu 1.2. Jeśli kiedyś przestanie
      # przechodzić, znaczy, że opisanie kolejnej domeny wymagało dopisania
      # słowa — czyli że DSL jest źle zaprojektowany, a nie że test jest
      # nieaktualny. **Wtedy poprawia się DSL, nie ten test.**
      #
      # `population` było jedynym słowem, które ten test oblało, i ma tendencję
      # do powrotu. Nie ma go tu i to jest celowe.
      assert PNS.Contract.vocabulary() == %{
               event: [:label, :owner, :payload, :retain, :depends_on, :identity, :process, :stage, :terminal],
               process: [:label, :stages, :instance, :cadence, :deadline, :unverified],
               external: [:label, :expected_latency, :unavailable_looks_like],
               rule: [:label, :function, :source],
               example: [:rule, :given, :command, :then, :rejected_with],
               trace: [:from, :eventually, :within, :or_else]
             }
    end

    test "obie domeny używają tego samego zestawu makr i żadna nie ma własnych" do
      makra =
        PNS.Contract.__info__(:macros)
        |> Keyword.keys()
        |> Enum.reject(&String.starts_with?(to_string(&1), "__"))
        |> Enum.sort()

      assert makra == [:event, :example, :external, :process, :rule, :trace]
    end

    test "kontrakt medyczny nie wnosi żadnego klucza, którego nie ma w słowniku" do
      # Sprawdzenie od drugiej strony: DSL odrzuca nieznane klucze w czasie
      # kompilacji, więc sam fakt, że ten moduł się skompilował, jest dowodem.
      # Test pilnuje, żeby dowód nie zniknął przez przypadkowe usunięcie pliku.
      assert function_exported?(@contract, :__pns_contract__, 0)
      assert length(@contract.events()) == 10
      assert Enum.map(@contract.processes(), & &1.name) == [:treatment_episode]
      assert Enum.map(@contract.traces(), & &1.name) == [:referral_reaches_a_decision, :episode_reaches_an_end]
      assert Enum.map(@contract.externals(), & &1.name) == [:payer_registry]
      assert Enum.map(@contract.rules(), & &1.name) == [:treatment_starts_only_on_confirmed_eligibility]
    end
  end

  describe "kształty, których TaxVision nie ma" do
    test "to samo zdarzenie wiele razy w jednym przebiegu jest wyrażalne" do
      # Tożsamość faktu zawiera numer wizyty, tożsamość przebiegu nie. Dziesięć
      # wizyt to dziesięć faktów w jednym epizodzie — nie dziesięć epizodów i
      # nie jeden fakt powtórzony. Bez rozdzielenia `identity` od `instance`
      # jedno z dwóch byłoby nie do wyrażenia.
      wizyta = @contract.event(:session_completed)
      proces = @contract.process(:treatment_episode)

      assert proces.instance == [:episode_id]
      assert wizyta.identity == [:episode_id, :session_no]
      assert proces.instance -- wizyta.identity == []
    end

    test "zdarzenie wchodzące bez komendy niesie tożsamość przebiegu samo z siebie" do
      skierowanie = @contract.event(:referral_received)

      assert Map.has_key?(skierowanie.payload, :episode_id)
      assert @contract.process_of(:referral_received).name == :treatment_episode
    end

    test "tożsamość przebiegu z jednego pola działa tak samo jak z dwóch" do
      assert @contract.process(:treatment_episode).instance == [:episode_id]
      assert @taxvision.process(:accounting_month).instance == [:company_id, :period]
    end

    test "proces zdarzeniowy nie ma kadencji i to jest wynik, nie przeoczenie" do
      # `cadence` odpowiada na pytanie „co jak często instancja jest należna".
      # Miesiąc księgowy jest należny co miesiąc; epizod leczenia nie jest
      # należny nigdy — zaczyna się, kiedy wpłynie skierowanie.
      #
      # Nie brakuje słowa: słowo jest opcjonalne i nie ma zastosowania. Ale
      # mechanizm, który na nim stoi — okno „never observed" — nie ma dla tego
      # procesu skąd wziąć długości, i to należy do notatek §9.
      assert @contract.process(:treatment_episode).cadence == nil
      assert @taxvision.process(:accounting_month).cadence == {1, :month}
    end
  end

  describe "bramy działają na drugim kontrakcie, nie tylko na pierwszym" do
    for {example, index} <- Enum.with_index(@contract.examples()) do
      @example example
      @rule @contract.rule(example.rule)

      test "przykład jest testem: #{example.description} (##{index})" do
        ContractExamples.run(@example, @rule)
      end
    end

    test "brama instancji policzyła klucz przebiegu dla zdarzenia z tej domeny" do
      {proces, instancja} =
        PNS.Instance.key(@contract, :session_completed, %{
          episode_id: "ep-7",
          session_no: 3,
          performed_at: "2026-08-05T09:00:00Z"
        })

      assert proces == "treatment_episode"
      assert instancja == "treatment_episode|ep-7"
    end

    test "rejestr silnika widzi oba kontrakty" do
      PNS.Registry.load!()
      assert @contract in PNS.Registry.contracts()
      assert @taxvision in PNS.Registry.contracts()
    end
  end

  describe "fake, bez implementacji" do
    test "niedostępny rejestr płatnika to brak rozstrzygnięcia, nie odmowa" do
      # Kontrakt mówi to samo słowami w `unavailable_looks_like`. Zlanie tych
      # dwóch stanów odbiera pacjentowi świadczenie z powodu awarii cudzego
      # serwera — i to jest ten sam błąd, przed którym ADR §11-12 ostrzega przy
      # rejestrach publicznych.
      assert {:error, :unavailable} = UniversalityGate.PayerRegistry.check("unavailable")

      assert @contract.external(:payer_registry).unavailable_looks_like =~ "nie odmowa"
    end

    test "odpowiedź rejestru wchodzi do funkcji decyzyjnej jako argument" do
      # Adapter wołany **w środku** funkcji decyzyjnej zabrałby jej możliwość
      # odróżnienia „płatnik odmówił" od „rejestr nie odpowiada".
      {:ok, odpowiedz} = UniversalityGate.PayerRegistry.check("p-1")

      emisje =
        UniversalityGate.Eligibility.decide(%{
          command: :qualify_referral,
          episode_id: "ep-1",
          patient_id: "p-1",
          identity_confirmed: true,
          payer: odpowiedz
        })

      assert :payer_eligibility_confirmed in Enum.map(emisje, & &1.name)
    end
  end
end
