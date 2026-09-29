defmodule Rehmed.Contracts.Settlement do
  @moduledoc """
  Settlement (`CTX-05`): what one visit costs, what was paid for it, how it closes,
  and the till's view of the day.

  Written anew on 28 September 2026 (v2 plan, E9) from `AGG-03` in
  `2-Solution/20-aggregates.md`, process 4 of
  `docs/rehmed-2026-08-18-distillation.md` and the client's later answers in
  `54-uwagi-K5-2026-09-09.md`. It replaces `Rehmed.Contracts.VisitSettlement`, the v2
  port of E6, and differs from it where the material moved after the port was
  written.

  ## The handover is a gate only when the scope changed

  `DEC-18` made the specialist hand every visit over, which froze the price. The
  client answered it (`K5-20`): a visit is handed over for settlement only when the
  specialist adds or changes a service, and the mockup built it on
  2026-09-14 — no button without a scope change, one button with it, and reception's
  settle greyed out until the handover. So two invariants: a handover needs a scope
  change, and a changed scope is settled only after the handover.

  What then opens a settlement and freezes the price is `H177`, open for pass 2. The
  mockup's answer is followed here: **the patient's presence opens it** (scheduling's
  `patient_arrived`, included in the run) and **the price freezes at the close**, so
  the total comes with the close. The mockup says itself that this contradicts
  `DEC-18`; if pass 2 decides otherwise, the total moves.

  ## Money

  An integer in grosze, the domain's `money`: sums are exact, and `AGG-03`
  invariant 1 is arithmetic — *payment lines sum to the settlement total* — with its
  failure on record: split payments flip sign in the incumbent, so the daily report
  is wrong on the days it matters (W1 02:02:07). A partial payment is refused rather
  than modelled: a short settlement is a receivable, and receivables are `AGG-20`'s.

  ## The day

  `R-07`, the day's summary per payment method, answers reception's question "is
  the till right". It reads the payments, per day and method; the day is the day the
  payment was taken. A correction carries the day it belongs to — the close's —
  never the day it was entered, which is the incumbent's defect (`E-84`). The day
  close itself (`E-83`, `AGG-07`) is out of E9.

  ## No promise

  The one timing anybody described is that a mid-visit addition reaches the desk
  before the patient does — a moment, answered by a push (`DEC-17`), with no interval
  to budget for.
  """

  use EhOsContract.Contract, domain: Rehmed.Domain, context: :settlement

  consumes Rehmed.Contracts.Scheduling, :patient_arrived

  aggregate :visit_settlement, "Rozliczenie wizyty" do
    identity :visit_id

    state do
      field :scope_changed, :boolean, default: false
      field :handed_over, :boolean, default: false
      field :payments, {:list, :money}, default: []
      field :closed_on, :date, optional: true
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
    # know either itself, since it opens only when the patient arrives.
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
      field :total, :money
      field :payer_id, :id, optional: true
      field :period_id, :id, optional: true

      constraint :payer_visit_names_its_period,
                 "Wizyta na płatnika wskazuje okres rozliczenia, a okres — płatnika",
                 source: "AGG-11 niezmiennik 4: płatnik × okres"
    end

    command :book_correction, "Zaksięguj korektę",
      by: :reception,
      emits: :settlement_corrected,
      source: "C-46, aktor A-02" do
      field :delta, :money
    end

    stage :charging do
      event :service_line_added, "Dodano dodatkową usługę do rozliczenia", source: "E-45" do
        field :service_id, {:id, :service}
      end

      # `E-115`, since `K5-20` only after a change of scope.
      event :visit_handed_over, "Wizyta oznaczona jako wykonana i gotowa do rozliczenia",
        source: "E-115, K5-20"
    end

    stage :payment do
      # `E-55`. A split across methods is allowed, and is where the incumbent flips
      # the sign.
      event :payment_recorded, "Pacjent opłacił wizytę", source: "E-55" do
        field :method, :payment_method
        field :amount, :money
      end

      event :visit_closed_commercially, "Recepcja zamknęła wizytę",
        terminal: true,
        source: "E-56" do
        field :total, :money
      end

      # The other meaning `C-30` carried; a visit a payer or a prepaid pass covers ends so
      # (`AGG-01` invariant 9), and `P-08` exists to notice the others.
      event :visit_closed_without_payment, "Zamknięto wizytę bez płatności",
        terminal: true,
        source: "E-53, P-08" do
        field :total, :money
      end

      # What crosses to external payers (`30-contexts.md`: "which visits a payer owes
      # for"), next to either close: a mixed visit is paid by the patient for what the
      # payer does not cover (`P-31`). The model has no fact for it, so this one is
      # ours (plan, the decision before E9b), and no amount: the payer's invoice is
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
    end
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

  # `DEC-01` made documentation and settlement independent and concurrent — the
  # specialist writes while reception settles — so no promise crosses them.
  process :visit_settlement, "Rozliczenie wizyty" do
    correlate :visit_id

    stage :opening do
      include :patient_arrived
    end

    stage :charging
    stage :payment
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
