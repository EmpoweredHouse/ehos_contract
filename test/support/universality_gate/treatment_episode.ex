defmodule UniversalityGate.TreatmentEpisode do
  @moduledoc """
  # TEN KONTRAKT JEST WYMYŚLONY. NIE JEST MATERIAŁEM KLIENCKIM.

  Nie stoi za nim żaden warsztat, żaden process owner i żaden klient. Rehmed
  startuje 10 sierpnia i **materiału z Rehmed jeszcze nie ma** — gdyby ten plik
  udawał kontekst kliencki, byłby dokładnie tym rodzajem wymyślonej wiedzy o
  domenie, którą PNS ma wykrywać u innych. Każda nazwa zdarzenia, każdy termin i
  każda reguła poniżej pochodzi z wyobraźni autora.

  Ten plik **nie ma prawa trafić do repozytorium kontekstu.** Mieszka w
  `test/support/`, bo jest fikstur silnika, a nie drzewem klienta.

  ## Po co więc jest

  To jest brama uniwersalności z etapu 1.2. Testuje **słownik DSL, nie wiedzę o
  domenie**: czy `event`, `process`, `stage`, `trace`, `instance`, `identity`,
  `cadence`, `deadline`, `external`, `rule`, `example`, `retain` i `unverified`
  wystarczają, żeby opisać proces, który z księgowością nie ma nic wspólnego.

  Kryterium jest twarde i pinuje je test: **zero nowych słów w DSL.** Do dziś
  jedyny dowód na uniwersalność brzmiał „jeden kontrakt, jedna domena, jeden
  autor", czyli nie był dowodem.

  Wybrane kształty, których TaxVision nie ma albo ma słabiej:

  | Kształt | Gdzie tutaj |
  | --- | --- |
  | Zdarzenie wchodzące bez komendy | `referral_received` — skierowanie wpływa z zewnątrz |
  | To samo zdarzenie wiele razy w jednym przebiegu | `session_completed`, raz na wizytę |
  | Tożsamość przebiegu z jednego pola | `instance: [:episode_id]` |
  | Proces bez kadencji | epizod zaczyna się od skierowania, nie od kalendarza |

  Ostatni wiersz jest jedynym miejscem, w którym coś tu zgrzytnęło, i jest to
  **brak słowa, nie brakujące słowo**: `cadence` jest opcjonalna i epizod jej po
  prostu nie ma. Szczegóły przy deklaracji procesu.
  """

  use PNS.Contract

  # --- kwalifikacja ---

  event :referral_received,
    label: "Wpłynęło skierowanie",
    # Właściciel wskazany, moduł nieistniejący — bo tu nie ma implementacji.
    # To ten sam stan, w którym `bank_statement_received` wskazuje
    # `Taxvision.Matching`: zadeklarowane, nieobsłużone.
    owner: UniversalityGate.Admissions,
    # Zdarzenie wchodzące **bez komendy**: skierowanie przychodzi z zewnątrz,
    # nikt go u nas nie wywołał. Payload musi więc nieść tożsamość przebiegu
    # sam z siebie — nie ma komendy, z której dałoby się ją dobrać.
    payload: %{episode_id: :id, patient_id: :id, referral_code: :id, received_at: :timestamp}

  event :patient_identity_confirmed,
    label: "Potwierdzono tożsamość pacjenta",
    owner: UniversalityGate.Admissions,
    payload: %{episode_id: :id, patient_id: :id, document_type: :enum}

  event :payer_eligibility_checked,
    label: "Sprawdzono uprawnienie do świadczenia w rejestrze płatnika",
    owner: UniversalityGate.Admissions,
    depends_on: :payer_registry,
    payload: %{episode_id: :id, checked_at: :timestamp}

  event :payer_eligibility_confirmed,
    label: "Uprawnienie do świadczenia potwierdzone",
    owner: UniversalityGate.Admissions,
    payload: %{episode_id: :id, scope: :enum}

  event :payer_eligibility_denied,
    label: "Odmowa uprawnienia do świadczenia",
    owner: UniversalityGate.Admissions,
    payload: %{episode_id: :id, reason: :string},
    # Powód odmowy to zdanie o zdrowiu pacjenta zestawione z decyzją płatnika.
    # Do logu idzie hash: dowód, że odmowa była i jaka, bez trzymania treści.
    retain: %{reason: :hash},
    # Ta sama odmowa nie mnoży faktów, inna owszem — dokładnie ten kształt, co
    # `diff` przy rozjeździe rejestrowym.
    identity: [:episode_id, :reason]

  # --- plan ---

  event :treatment_plan_approved,
    label: "Zatwierdzono plan leczenia",
    owner: UniversalityGate.Planning,
    # `approved_by` zostaje w payloadzie i **nie jest** duplikatem `actor` —
    # to jest granica, którą warto umieć postawić. `actor` mówi, kto wykonał
    # operację w systemie; tu chodzi o to, kto **firmuje plan leczenia**, co
    # jest faktem o odpowiedzialności zawodowej. Rejestratorka wprowadzająca
    # plan w imieniu lekarza to dwie różne osoby w tym samym zdarzeniu.
    #
    # Typ `:id`, nie `:string`: identyfikator osoby, nie jej imię wpisane
    # ręcznie. Ta różnica decyduje, czy do logu trafiają dane osobowe.
    payload: %{episode_id: :id, session_count: :integer, approved_by: :id}

  # --- realizacja ---

  event :session_completed,
    label: "Zrealizowano wizytę",
    owner: UniversalityGate.Sessions,
    payload: %{episode_id: :id, session_no: :integer, performed_at: :timestamp},
    # **To samo zdarzenie wiele razy w jednym przebiegu.** Tożsamość faktu
    # zawiera numer wizyty, tożsamość przebiegu nie — więc dziesięć wizyt to
    # dziesięć faktów w jednym epizodzie, a nie dziesięć epizodów ani jeden
    # fakt powtórzony. Bez tego rozdzielenia jedno z dwóch byłoby nie do
    # wyrażenia.
    identity: [:episode_id, :session_no]

  event :session_missed,
    label: "Pacjent nie stawił się na wizytę",
    owner: UniversalityGate.Sessions,
    payload: %{episode_id: :id, session_no: :integer, noted_at: :timestamp},
    identity: [:episode_id, :session_no]

  # --- zamknięcie ---

  event :episode_closed,
    label: "Zamknięto epizod leczenia",
    owner: UniversalityGate.Sessions,
    payload: %{episode_id: :id, outcome: :enum}

  event :episode_abandoned,
    label: "Przerwano epizod leczenia",
    owner: UniversalityGate.Sessions,
    payload: %{episode_id: :id, reason: :string},
    retain: %{reason: :hash}

  # --- proces ---

  process :treatment_episode,
    label: "Epizod leczenia: od skierowania do zamknięcia",
    stages: [
      qualification: [
        :referral_received,
        :patient_identity_confirmed,
        :payer_eligibility_checked,
        :payer_eligibility_confirmed,
        :payer_eligibility_denied
      ],
      plan: [:treatment_plan_approved],
      treatment: [:session_completed, :session_missed],
      closing: [:episode_closed, :episode_abandoned]
    ],
    # Odmowa płatnika kończy proces tak samo jak zamknięcie epizodu: skończył
    # się, tylko nie tak, jak chcieliśmy. Ten sam kształt co zablokowanie
    # miesiąca na rozjeździe.
    terminal: [:episode_closed, :episode_abandoned, :payer_eligibility_denied],
    # Jeden przebieg to jeden epizod. Jedno pole wystarcza, bo epizod jest
    # nadawany, a nie składany z firmy i okresu — i to jest różnica wobec
    # TaxVision, którą DSL obsłużył bez zmiany.
    instance: [:episode_id],
    # **`cadence:` świadomie nie ma i to jest wynik bramy, nie przeoczenie.**
    #
    # Kadencja odpowiada na pytanie „co jak często instancja jest należna" i z
    # niej liczy się okno „never observed". Miesiąc księgowy jest należny co
    # miesiąc. Epizod leczenia nie jest należny nigdy — zaczyna się, kiedy
    # wpłynie skierowanie. Nie brakuje tu słowa: słowo jest opcjonalne i po
    # prostu nie ma zastosowania.
    #
    # Konsekwencja jest realna i należy do notatek §9, nie do tego pliku:
    # dla procesów zdarzeniowych okno „never observed" nie ma skąd wziąć
    # długości i spada na fallback z zaobserwowanych odstępów.
    deadline: {30, :day},
    # Wszystko w tym kontrakcie jest wymyślone, ale `deadline` jest jedyną
    # deklaracją, która **udaje liczbę z rzeczywistości** — reszta to nazwy i
    # kształty. Bez tego oznaczenia raport dowodowy liczyłby wymyślony termin
    # jako zmierzony.
    unverified: [:deadline]

  # --- assercje ---

  trace :referral_reaches_a_decision do
    from :referral_received
    eventually :payer_eligibility_confirmed, within: {3, :day}
    or_else :payer_eligibility_denied
  end

  trace :episode_reaches_an_end do
    from :treatment_plan_approved
    eventually :episode_closed, within: {90, :day}
    or_else :episode_abandoned
  end

  # --- zależność zewnętrzna, nazwana faktem, nie vendorem ---

  external :payer_registry,
    label: "Rejestr płatnika: potwierdzenie uprawnienia do świadczenia",
    expected_latency: {5, :second},
    unavailable_looks_like: "brak odpowiedzi — uprawnienie nierozstrzygnięte, nie odmowa"

  # --- reguła i przykłady (ADR §18) ---

  rule :treatment_starts_only_on_confirmed_eligibility,
    label: "Bez potwierdzonej tożsamości i uprawnienia leczenie się nie zaczyna",
    function: {UniversalityGate.Eligibility, :decide, 1},
    source: "WYMYŚLONE. Nie ma warsztatu, nie ma process ownera — patrz moduledoc."

  example "tożsamość potwierdzona i aktywne uprawnienie — kwalifikacja przechodzi",
    rule: :treatment_starts_only_on_confirmed_eligibility,
    given: %{
      identity_confirmed: true,
      payer: %{status: "aktywne", scope: "rehabilitacja ambulatoryjna"}
    },
    command: {:qualify_referral, %{episode_id: "ep-1", patient_id: "p-1"}},
    then: [:payer_eligibility_confirmed]

  example "uprawnienie wygasło — odmowa zamiast kwalifikacji",
    rule: :treatment_starts_only_on_confirmed_eligibility,
    given: %{
      identity_confirmed: true,
      payer: %{status: "wygasłe", scope: nil}
    },
    command: {:qualify_referral, %{episode_id: "ep-1", patient_id: "p-1"}},
    then: [:payer_eligibility_denied]

  example "tożsamość niepotwierdzona — komenda odrzucona, rejestru nawet nie pytamy",
    rule: :treatment_starts_only_on_confirmed_eligibility,
    given: %{
      identity_confirmed: false,
      payer: %{status: "aktywne", scope: "rehabilitacja ambulatoryjna"}
    },
    command: {:qualify_referral, %{episode_id: "ep-1", patient_id: "p-1"}},
    rejected_with: :patient_identity_not_confirmed
end
