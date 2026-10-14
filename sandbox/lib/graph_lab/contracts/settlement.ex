defmodule GraphLab.Contracts.Settlement do
  @moduledoc """
  **Part of the test set for drawing the graph; not client material** (`GraphLab`).

  Settlement: what a visit costs, what was paid for it, how it closes — paid, without
  payment, or charged to an external payer — its corrections, and the day's payments per
  method.

  A process manager starts on scheduling's `visit_completed`, which makes settlement the
  third contract consuming that event, and flags a visit nobody settled eight hours
  later. No material names that interval: it is here for the graph.
  """

  use EhOsContract.Contract,
    domain: GraphLab.Domain,
    context: :settlement,
    id: "graph-lab.settlement"

  consumes GraphLab.Contracts.Scheduling, :visit_completed

  aggregate :visit_settlement, "Rozliczenie wizyty" do
    identity visit_id: {:id, :visit}

    state do
      field :scope_changed, :boolean, default: false
      field :handed_over, :boolean, default: false
      field :payments, {:list, :money}, default: []
      field :closed_on, :date, optional: true
      # What the close settled, and whether anything but a correction followed it: what
      # `holds?/2` reads to say the invariants hold.
      field :total, :money, optional: true
      field :changed_after_close, :boolean, default: false
    end

    invariant :handover_only_after_scope_change,
              "Specjalista przekazuje wizytę do rozliczenia tylko wtedy, gdy dodał lub zmienił usługę",
              source: "K5-20 (54-uwagi-K5, 2026-09-09)"

    invariant :changed_scope_handed_over_before_settlement,
              "Wizytę ze zmienionym zakresem usług recepcja rozlicza dopiero po jej przekazaniu",
              source: "K5-20, makieta 2026-09-14"

    invariant :payment_lines_sum_to_total, "Linie płatności sumują się do wartości rozliczenia",
      source: "W1 02:02:07; AGG-03 niezmiennik 1"

    # Without it a closed visit takes a payment and a second close, and the day its
    # corrections belong to moves with the second close.
    invariant :closed_settlement_changes_only_by_correction,
              "Rozliczonej wizyty nie zmienia się po cichu — zmiana to korekta",
              source: "AGG-03 niezmiennik 4"

    # A correction is booked after the day closed (`E-84`): before the visit is settled
    # there is no day it belongs to, and nothing to correct.
    invariant :only_a_settled_visit_is_corrected,
              "Korektę księguje się tylko na rozliczonej wizycie",
              source: "E-84; AGG-03 niezmiennik 4"

    # `E-45`, and the one write a specialist may not defer: adding a service changes
    # the price and the duration, and the patient does not leave until it is
    # confirmed. No amount: the fact is that a service joined.
    command :add_service_line, "Dodaj usługę do rozliczenia",
      by: :specialist,
      emits: :service_line_added,
      rejects: :closed_settlement_changes_only_by_correction,
      source: "C-23, aktor A-03" do
      field :service_id, {:id, :service}
    end

    command :hand_over_visit, "Przekaż do rozliczenia",
      by: :specialist,
      emits: :visit_handed_over,
      rejects: :handover_only_after_scope_change,
      source: "C-68, aktor A-03; K5-20"

    command :record_payment, "Przyjmij płatność",
      by: :reception,
      emits: :payment_recorded,
      rejects: :closed_settlement_changes_only_by_correction,
      source: "C-31, aktor A-02" do
      field :method, :payment_method
      field :amount, :money
    end

    # `C-30` produces `E-53 / E-56`: both endings are this command's. The total comes
    # with it, since the price freezes at the close (`H177`, mockup).
    #
    # With payments, the total is what they sum to, so for a visit a payer covers in
    # part it is the patient's part: the payer's line settles at 0 (`P-31`). Without
    # any, it is the price somebody else covers.
    #
    # So do the payer and the period, when a payer covers the visit: the payer is set
    # at booking and the settlement screen shows it on the line it covers (the
    # mockup's "who pays" column), and the period is the month of the visit. The settlement cannot
    # know either itself, since both are set at booking, which it does not consume.
    command :close_settlement, "Zamknij wizytę komercyjnie",
      by: :reception,
      emits: [:visit_closed_commercially, :visit_closed_without_payment, :visit_charged_to_payer],
      rejects: [
        :closed_settlement_changes_only_by_correction,
        :changed_scope_handed_over_before_settlement,
        :payment_lines_sum_to_total,
        :payer_visit_names_its_period
      ],
      source: "C-30, aktor A-02" do
      # The total by the rule above, not reception's to say: the host gives it from the
      # visit's price and who pays (`EhOsContract.Supplier`).
      field :total, :money, supplied_by: :host
      field :payer_id, :id, optional: true
      field :period_id, :id, optional: true

      constraint :payer_visit_names_its_period,
                 "Wizyta na płatnika wskazuje okres rozliczenia, a okres — płatnika",
                 source: "AGG-11 niezmiennik 4: płatnik × okres"
    end

    # Issued by the chase only, so no actor may.
    command :flag_unsettled_visit, "Oznacz wizytę nierozliczoną",
      emits: :unsettled_visit_flagged,
      source: "dodane do testów grafu"

    command :book_correction, "Zaksięguj korektę",
      by: :reception,
      emits: :settlement_corrected,
      rejects: :only_a_settled_visit_is_corrected,
      source: "C-46, aktor A-02" do
      field :delta, :money
    end

    event :service_line_added, "Dodano dodatkową usługę do rozliczenia", source: "E-45" do
      field :service_id, {:id, :service}
    end

    # `E-115`, since `K5-20` only after a change of scope.
    event :visit_handed_over, "Wizyta oznaczona jako wykonana i gotowa do rozliczenia",
      source: "E-115, K5-20"

    # `E-55`. A split across methods is allowed, and is where the incumbent flips
    # the sign.
    event :payment_recorded, "Pacjent opłacił wizytę", source: "E-55" do
      field :method, :payment_method
      field :amount, :money
    end

    event :visit_closed_commercially, "Recepcja zamknęła wizytę", source: "E-56" do
      field :total, :money
    end

    # The other meaning `C-30` carried; a visit a payer or a prepaid pass covers ends so
    # (`AGG-01` invariant 9), and `P-08` exists to notice the others.
    event :visit_closed_without_payment, "Zamknięto wizytę bez płatności", source: "E-53, P-08" do
      field :total, :money
    end

    # What crosses to external payers (`30-contexts.md`: "which visits a payer owes
    # for"), next to either close: a mixed visit is paid by the patient for what the
    # payer does not cover (`P-31`). The model has no fact for it, so this one is
    # ours, and no amount: the payer's invoice is
    # made outside the system (`H62`).
    event :visit_charged_to_payer, "Wizyta obciąża płatnika zewnętrznego",
      source: "30-contexts.md, CTX-05 → CTX-06" do
      field :payer_id, :id
      field :period_id, :id
    end

    # `E-84`. `delta` may be negative, so a refund needs no event of its own.
    event :settlement_corrected, "Zaksięgowano korektę po zamknięciu dnia", source: "E-84" do
      field :delta, :money
      field :business_date, :date
    end

    event :unsettled_visit_flagged, "Wizyta bez rozliczenia na koniec dnia",
      source: "dodane do testów grafu"
  end

  # The settlement's counterpart of the documentation chase.
  process_manager :settlement_chase, "Pogoń za rozliczeniem wizyty" do
    correlate :visit_id
    starts_on :visit_completed, sets: :settlement_due

    timer :settlement_due, "Koniec dnia bez rozliczenia",
      wait: {8, :hour},
      issues: :flag_unsettled_visit

    ends_on :visit_closed_commercially
    ends_on :visit_closed_without_payment
  end

  read_model :daily_totals, "Zestawienie dnia per metoda płatności",
    projects: :payment_recorded do
    field :business_date, :date
    field :method, :payment_method
    field :total, :money
  end

  query :daily_totals_for, "Zestawienie dnia dla recepcji",
    reads: :daily_totals,
    by: :reception do
    param :business_date, :date
  end

  scenario "osiem godzin po wyjściu pacjenta bez rozliczenia — wizyta oznaczona" do
    target :settlement_chase
    given :visit_completed
    on :settlement_due
    issues :flag_unsettled_visit
  end

  scenario "pogoń oznacza wizytę jako nierozliczoną" do
    command :flag_unsettled_visit
    expect :unsettled_visit_flagged
  end

  scenario "korekta przed rozliczeniem wizyty — odrzucona" do
    command :book_correction, %{delta: -1_000}
    rejected :only_a_settled_visit_is_corrected
  end

  # VLW 00:19:58: an unpaid penalty is collected with the next visit, "pay 200 zł at
  # once, not 150". A 150 zł visit and a 50 zł penalty are 200 zł.
  scenario "wizyta 150 zł i kara 50 zł, zapłacone 200 zł — rozliczenie się zamyka" do
    given :payment_recorded, %{method: :card, amount: 20_000}
    command :close_settlement, %{total: 20_000}
    expect :visit_closed_commercially, %{total: 20_000}
  end

  scenario "ta sama kwota w dwóch liniach — split jest poprawny, nie defektem" do
    given :payment_recorded, %{method: :card, amount: 15_000}
    given :payment_recorded, %{method: :cash, amount: 5_000}
    command :close_settlement, %{total: 20_000}
    expect :visit_closed_commercially
  end

  scenario "zapłacone 150 zł przy należnych 200 — rozliczenie odrzucone" do
    given :payment_recorded, %{method: :card, amount: 15_000}
    command :close_settlement, %{total: 20_000}
    rejected :payment_lines_sum_to_total
  end

  scenario "nic nie zapłacono — wizyta zamyka się bez płatności, i to jest legalne" do
    command :close_settlement, %{total: 20_000}
    expect :visit_closed_without_payment
  end

  scenario "wizyta w całości na LuxMed — zamyka się bez płatności i obciąża płatnika za wrzesień" do
    command :close_settlement, %{total: 18_000, payer_id: "payer-luxmed", period_id: "2026-09"}
    expect :visit_closed_without_payment
    expect :visit_charged_to_payer, %{payer_id: "payer-luxmed", period_id: "2026-09"}
  end

  # P-31: the service booked for LuxMed settles at 0, and what was added in the room
  # the patient pays.
  scenario "wizyta mieszana — pacjent płaci 50 zł za dodaną usługę, reszta obciąża LuxMed" do
    given :service_line_added, %{service_id: "service-ultrasound"}
    given :visit_handed_over
    given :payment_recorded, %{method: :card, amount: 5_000}
    command :close_settlement, %{total: 5_000, payer_id: "payer-luxmed", period_id: "2026-09"}
    expect :visit_closed_commercially, %{total: 5_000}
    expect :visit_charged_to_payer, %{payer_id: "payer-luxmed", period_id: "2026-09"}
  end

  scenario "płatnik bez okresu — rozliczenie odrzucone, zanim płatnik zgubi wizytę" do
    command :close_settlement, %{total: 18_000, payer_id: "payer-luxmed"}
    rejected :payer_visit_names_its_period
  end

  scenario "zakres bez zmian — specjalista nie ma czego przekazywać" do
    command :hand_over_visit
    rejected :handover_only_after_scope_change
  end

  scenario "specjalista dodał usługę — przekazuje wizytę do rozliczenia" do
    given :service_line_added, %{service_id: "service-ultrasound"}
    command :hand_over_visit
    expect :visit_handed_over
  end

  scenario "usługa dodana, wizyta nieprzekazana — recepcja jeszcze nie rozlicza" do
    given :service_line_added, %{service_id: "service-ultrasound"}
    given :payment_recorded, %{method: :card, amount: 20_000}
    command :close_settlement, %{total: 20_000}
    rejected :changed_scope_handed_over_before_settlement
  end

  scenario "wizyta rozliczona — kolejna płatność odrzucona, zmiana idzie korektą" do
    given :payment_recorded, %{method: :card, amount: 20_000}
    given :visit_closed_commercially, %{total: 20_000}
    command :record_payment, %{method: :cash, amount: 5_000}
    rejected :closed_settlement_changes_only_by_correction
  end

  scenario "dzień: dwie płatności kartą i jedna gotówką — suma per metoda" do
    given :payment_recorded, %{visit_id: "visit-anna", method: :card, amount: 15_000}
    given :payment_recorded, %{visit_id: "visit-ben", method: :card, amount: 10_000}
    given :payment_recorded, %{visit_id: "visit-anna", method: :cash, amount: 5_000}
    query :daily_totals_for, %{business_date: "2026-01-01"}

    answers [
      %{method: :card, total: 25_000},
      %{method: :cash, total: 5_000}
    ]
  end
end
