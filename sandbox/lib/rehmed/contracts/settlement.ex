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
  client answered it (`K5-20`): *„przekazana do rozliczenia ma być wyłącznie w
  przypadku gdy specjalista doda lub zmieni usługę”*, and the mockup built it on
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

  `R-07`, „Zestawienie dnia per metoda płatności”, answers reception's question "is
  the till right". It reads the payments, per day and method; the day is the day the
  payment was taken. A correction carries the day it belongs to — the close's —
  never the day it was entered, which is the incumbent's defect (`E-84`). The day
  close itself (`E-83`, `AGG-07`) is out of E9.

  ## No promise

  The one timing anybody described is that a mid-visit addition reaches the desk
  before the patient does — a moment, answered by a push (`DEC-17`), with no interval
  to budget for.
  """

  use EhOsContract.Next.Contract, domain: Rehmed.Domain, context: :settlement

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

    # `E-45`, and the one write a specialist may not defer: adding a service changes
    # the price and the duration, and the patient does not leave until it is
    # confirmed. No amount: the fact is that a service joined.
    command :add_service_line, "Dodaj usługę do rozliczenia",
      by: :specialist,
      emits: :service_line_added,
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
      source: "C-31, aktor A-02" do
      field :method, :payment_method
      field :amount, :money
    end

    # `C-30` produces `E-53 / E-56`: both endings are this command's. The total comes
    # with it, since the price freezes at the close (`H177`, mockup).
    command :close_settlement, "Zamknij wizytę komercyjnie",
      by: :reception,
      emits: [:visit_closed_commercially, :visit_closed_without_payment],
      rejects: [:changed_scope_handed_over_before_settlement, :payment_lines_sum_to_total],
      source: "C-30, aktor A-02" do
      field :total, :money
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

      # The other meaning `C-30` carried; a visit a payer or a karnet covers ends so
      # (`AGG-01` invariant 9), and `P-08` exists to notice the others.
      event :visit_closed_without_payment, "Zamknięto wizytę bez płatności",
        terminal: true,
        source: "E-53, P-08" do
        field :total, :money
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
