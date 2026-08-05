defmodule Taxvision.Contracts.AccountingMonth do
  @moduledoc """
  Otwarcie miesiąca księgowego — faza 3.1 warsztatu TaxVision.

  Wszystkie nazwy zdarzeń pochodzą z warsztatu, żadna nie jest wymyślona.
  Źródło: `workshop_output/02-event-storming.md`, sekcja 3.1, polityka P1 z
  sekcji 10, niezmienniki agregatu `AccountingMonth` z sekcji 12.

  Kontrakt rejestruje się sam — nie ma modułu agregującego. Moduł-rodzic
  włączający dzieci wygląda porządnie i przywraca problem: rodzic zależy od
  każdego dziecka w czasie kompilacji, handlery zależą od rodzica, więc jedno
  zdarzenie rekompiluje wszystko.
  """

  use PNS.Contract

  # --- faza 3.1: zaimplementowana ---

  event :data_completeness_confirmed,
    label: "Potwierdzono komplet danych historycznych",
    owner: Taxvision.RegistryCheck,
    # Nie ma tu `confirmed_by`. Kto potwierdził, wie **silnik** — `actor` jest
    # kolumną logu, niesioną przez każde zdarzenie, przechodzącą przez
    # `causation` i przez granicę joba. Pole w payloadzie powielałoby tę samą
    # prawdę w drugim miejscu, a dwa źródła prawdy o jednym fakcie rozjeżdżają
    # się dokładnie wtedy, kiedy są potrzebne do audytu.
    payload: %{company_id: :id, period: :period}

  event :registry_status_checked,
    label: "Sprawdzono status w CEIDG/KRS, białym rejestrze VAT i VIES",
    owner: Taxvision.RegistryCheck,
    depends_on: :registries,
    payload: %{company_id: :id, period: :period, checked_at: :timestamp}

  event :registry_check_logged,
    label: "Zapisano datę ostatniego sprawdzenia rejestrów",
    owner: Taxvision.RegistryCheck,
    payload: %{company_id: :id, period: :period, checked_at: :timestamp}

  event :registry_data_consistent,
    label: "Dane firmy zgadzają się z rejestrami",
    owner: Taxvision.RegistryCheck,
    payload: %{company_id: :id, period: :period}

  event :registry_discrepancy_detected,
    label: "Dane firmy nie zgadzają się z rejestrami",
    owner: Taxvision.RegistryCheck,
    payload: %{company_id: :id, period: :period, diff: :string},
    # Diff niesie dane firmy zestawione z rejestrami publicznymi. Do logu idzie
    # hash: dowód, że rozjazd był i jaki, bez trzymania treści na zawsze.
    retain: %{diff: :hash},
    # Tożsamość faktu obejmuje **treść** rozjazdu, nie tylko firmę i miesiąc.
    # Wersja bez `diff` miała dziurę, której się nie widzi: gdy 1 lipca rozjazd
    # jest na statusie VAT, a 5 lipca na formie prawnej, drugi problem zostałby
    # połknięty przez klucz pierwszego. Ten sam rozjazd = jedno powiadomienie,
    # inny rozjazd = nowe.
    #
    # `diff` jest hashowany przez `retain`, i to jest tu zaletą: klucz jest
    # deterministyczny, więc idempotencja działa, a jednocześnie nie zawiera
    # danych firmy zestawionych z rejestrami.
    identity: [:company_id, :period, :diff]

  event :monthly_tasks_generated,
    label: "Utworzono taski z szablonu na nowy miesiąc",
    owner: Taxvision.Tasks,
    payload: %{company_id: :id, period: :period, task_count: :integer}

  event :accounting_month_opened,
    label: "Otwarto miesiąc księgowy",
    owner: Taxvision.AccountingMonth,
    payload: %{company_id: :id, period: :period}

  event :discrepancy_notification_sent,
    label: "Wysłano powiadomienie o rozjeździe do księgowej i klienta",
    owner: Taxvision.Notifications,
    payload: %{company_id: :id, period: :period, recipients: :integer}

  # --- fazy 3.2-3.4: zadeklarowane, celowo niezaimplementowane ---
  #
  # To nie jest niedokończona robota. To demo stanu "declared, never observed"
  # (notatki §5, §9): `mix pns.check` i `mix pns.graph --overlay` mają je
  # wypisać jako martwe ścieżki, bo dokładnie tak wygląda kontrakt, który
  # wyprzedza implementację — czyli normalny stan w trakcie wdrożenia.

  event :bank_statement_received,
    label: "Otrzymano wyciąg bankowy (MT940/CSV; PDF nie wchodzi)",
    owner: Taxvision.Matching,
    payload: %{company_id: :id, period: :period, format: :enum}

  event :turnover_matched_with_invoice,
    label: "Sparowano obrót z fakturą",
    owner: Taxvision.Matching,
    # `period` dołożony przez bramę instancji i **nie jest kosmetyką**: bez
    # niego sparowany obrót nie mówi, do którego miesiąca należy, więc
    # meczowanie z lipca liczyłoby się jako postęp w przebiegu sierpniowym.
    # To jedyne zdarzenie w tym kontrakcie, które bramy nie przeszło.
    payload: %{company_id: :id, period: :period, turnover_id: :id, invoice_id: :id}

  event :month_closed,
    label: "Zamknięto miesiąc księgowy",
    owner: Taxvision.AccountingMonth,
    payload: %{company_id: :id, period: :period}

  # --- proces ---

  # **Jeden proces, cztery fazy — i tylko między fazami jest kolejność.**
  #
  # Warsztat mówi: "to jest jeden długi proces: od weryfikacji rejestrowej na
  # początku miesiąca po zamknięcie miesiąca", faza 3.1 jest bramką otwierającą,
  # 3.2-3.4 to kroki steppera. I zaraz potem: "fazy nie są w pełni sekwencyjne
  # … sekwencyjne są bramki" — bez pozytywnej weryfikacji miesiąc się nie
  # otwiera, bez wyciągu nie ma meczowania, bez meczowania nie ma eksportu.
  #
  # Dlatego kolejność jest zadeklarowana między fazami, a wewnątrz fazy nie ma
  # jej wcale. Na tym stoi wykrywanie krawędzi wstecznych, więc to nie jest
  # kosmetyka: check może być tylko tak prawdziwy jak model, na którym stoi.
  process :accounting_month,
    label: "Cykl miesięczny księgowy",
    # Nazwy faz są **identyfikatorami, nie etykietami** — idą do `pns.check`,
    # do grafu i do klucza wersji kontraktu, więc są po angielsku jak reszta
    # kodu. Po polsku jest to, co czyta klient: `label` i opisy przykładów.
    stages: [
      verification: [
        :data_completeness_confirmed,
        :registry_status_checked,
        :registry_check_logged,
        :registry_data_consistent,
        :registry_discrepancy_detected,
        :discrepancy_notification_sent
      ],
      opening: [
        :monthly_tasks_generated,
        :accounting_month_opened
      ],
      collection: [:bank_statement_received],
      matching: [:turnover_matched_with_invoice],
      closing: [:month_closed]
    ],
    # Zablokowanie na rozjeździe jest stanem końcowym tak samo jak zamknięcie
    # miesiąca: proces się skończył, tylko nie tak, jak chcieliśmy.
    terminal: [:month_closed, :discrepancy_notification_sent],
    # Jeden przebieg to **jedna firma w jednym miesiącu**. To ten sam klucz, po
    # którym warsztat mówi o rozliczeniu ("rozliczany jest miesiąc w tył"), i
    # to jest granica, w której liczy się assercja: otwarcie miesiąca dla c-2
    # nie zalicza niczego przebiegowi c-1.
    instance: [:company_id, :period],
    # Rozliczany jest miesiąc w tył, a sprawdzenie 1. dnia miesiąca wystarczy
    # [WF 00:34:40]. Z tego liczy się okno "never observed" — bez cadence
    # miesięczny proces czyta się jako martwy szósty dzień po ostatnim przebiegu.
    cadence: {1, :month},
    deadline: {25, :day},
    # 25. to prawdziwy ustawowy termin JPK_V7, więc liczba jest prawdopodobna —
    # ale **nikt z TaxVision jej nie podał**, a termin wysyłki deklaracji to nie
    # to samo co termin zamknięcia prac w biurze. Dopóki process owner nie
    # potwierdzi, to zdarzenie nie liczy się do raportu dowodowego.
    unverified: [:deadline]

  # --- assercja ---

  trace :month_opens_or_is_blocked do
    from :data_completeness_confirmed
    eventually :accounting_month_opened, within: {2, :day}
    or_else :discrepancy_notification_sent
  end

  # --- zależności zewnętrzne, nazwane faktem, nie vendorem ---

  external :registries,
    label: "Rejestry publiczne: CEIDG/KRS, biały rejestr VAT, VIES",
    expected_latency: {10, :second},
    unavailable_looks_like: "timeout albo pusta odpowiedź — weryfikacja zawieszona, nie negatywna"

  # --- reguły i przykłady (ADR §18) ---

  rule :month_opens_only_on_consistent_registry,
    label: "Bez zgodnej weryfikacji rejestrowej miesiąc się nie otwiera",
    function: {Taxvision.RegistryCheck, :decide, 1},
    source: "Warsztat WF 00:34:17-00:36:07 (polityka P1), WF 00:35:41"

  example "komplet danych i zgodne rejestry — miesiąc się otwiera",
    rule: :month_opens_only_on_consistent_registry,
    given: %{
      completeness_confirmed: true,
      abilia: %{legal_form: "JDG", vat_status: "czynny"},
      registries: %{legal_form: "JDG", vat_status: "czynny", vies_status: "aktywny"}
    },
    command: {:open_month, %{company_id: "c-1", period: "2026-07"}},
    # Tylko to zdarzenie jest treścią tej reguły. `then:` znaczy "wśród
    # wyemitowanych, w tej kolejności" — nie "dokładnie te".
    then: [:registry_data_consistent]

  example "rozjazd statusu VAT — blokada i powiadomienie zamiast otwarcia",
    rule: :month_opens_only_on_consistent_registry,
    given: %{
      completeness_confirmed: true,
      abilia: %{legal_form: "JDG", vat_status: "czynny"},
      registries: %{legal_form: "JDG", vat_status: "wykreślony", vies_status: "aktywny"}
    },
    command: {:open_month, %{company_id: "c-1", period: "2026-07"}},
    then: [:registry_discrepancy_detected]

  example "brak potwierdzenia kompletu danych — komenda odrzucona",
    rule: :month_opens_only_on_consistent_registry,
    given: %{
      completeness_confirmed: false,
      abilia: %{legal_form: "JDG", vat_status: "czynny"},
      registries: %{legal_form: "JDG", vat_status: "czynny", vies_status: "aktywny"}
    },
    command: {:open_month, %{company_id: "c-1", period: "2026-07"}},
    rejected_with: :data_completeness_not_confirmed

  # Trzeci poziom IAM: reguła domenowa. Nie do wyrażenia w konfiguracji
  # providera tożsamości, bo provider nie wie nic o miesiącu księgowym ani o
  # tym, czyja to firma.
  rule :only_company_accountant_opens_month,
    label: "Miesiąc otwiera księgowa przypisana do tej firmy, nie klient i nie księgowa innej firmy",
    function: {Taxvision.Authorization, :authorize_open_month, 1},
    source: "Warsztat: aktor fazy 3.1 to Księgowa + System; HS28 (model dwóch osi dostępu)"

  example "księgowa własnej firmy — wolno",
    rule: :only_company_accountant_opens_month,
    given: %{actor_roles: ["accounting"], actor_company: "c-1"},
    command: {:open_month, %{company_id: "c-1", period: "2026-07"}},
    then: []

  example "księgowa innej firmy — nie wolno, i to nie jest 403 od providera",
    rule: :only_company_accountant_opens_month,
    given: %{actor_roles: ["accounting"], actor_company: "c-2"},
    command: {:open_month, %{company_id: "c-1", period: "2026-07"}},
    rejected_with: :not_this_company
end
