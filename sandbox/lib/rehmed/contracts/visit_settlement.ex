defmodule Rehmed.Contracts.VisitSettlement do
  @moduledoc """
  The commercial side of one visit: what it costs, who pays, and the declaration
  that it is finished.

  Distilled from process 4 of
  [`docs/rehmed-2026-08-18-distillation.md`](../../../docs/rehmed-2026-08-18-distillation.md)
  (`AGG-03`, `E-45`, `E-55`, `E-56`, `E-84`, `DEC-05`, `DEC-18`). **`status: open`
  throughout**, and one declaration below rests on the single most contested
  decision in the source model — see the handoff.

  **Ported to the v2 DSL on 26 September 2026 (v2 plan, E6), and the port translates
  rather than fixes** (v2 §4.5). What the v1 contract said still holds unless a
  paragraph below says what changed and why. Its decision moved from
  `Rehmed.Settlement.decide/1` into `Rehmed.Settlement.VisitSettlement`, and its
  examples became scenarios.

  ## Money, which is what this contract was written to confront

  The two Rehmed contracts before this one carried no amounts. Neither did
  TaxVision — `turnover_matched_with_invoice` pairs a turnover with an invoice by
  identifier and records no value, in an **accounting** product. Three contracts,
  zero amounts, and it never read as a gap.

  It stops working here, because `AGG-03`'s invariant is arithmetic: *payment lines
  sum to the settlement total*, and its failure is on record — split payments flip
  sign, so the daily report is wrong on exactly the days it matters.

  **The type is an integer in grosze, and that is not a workaround.** Minor units in
  an integer are the correct representation for money: sums and comparisons are
  exact, and a decimal written as text gives up arithmetic.

  **What v1 was missing was a way to say what a number counts**, and v1 made do with
  a naming convention: every amount ended in `_minor`. A convention is not a
  guarantee, and v1's moduledoc said so. In v2 the domain says it:
  `value :money, :integer, unit: :grosze` in `Rehmed.Domain`, so the fields are
  `total`, `amount` and `delta`, typed `:money` (F3 in v2 §16). `money` is a word of
  Rehmed's domain, not of the library, which is what v1 wanted when it refused a
  `:money` type: the library still knows shapes, and a client's vocabulary lives in
  the client's domain.

  ### Where an amount is carried, and where it is not

  Not every number belongs in a payload. The test applied here is whether **the
  number is the fact, or an attribute of the thing the fact is about**:

  | Event | Amount? | Why |
  | --- | --- | --- |
  | `payment_recorded` | **yes** | the fact *is* an amount tendered by a method |
  | `visit_handed_over` | **yes** | the fact is that this total is now final |
  | `settlement_corrected` | **yes** | a correction is a delta and nothing else |
  | `service_line_added` | no | the fact is that a service joined the settlement; its price is an attribute of that line |

  This is a judgement, not a rule the engine enforces.

  ## Two more things the material forced

  **An attribute that exists only sometimes.** `DEC-05` says a settlement carries
  several payer lines, *each naming its payer* — and a privately paid line has no
  payer to name. v1 could not declare a field that is sometimes absent, so
  `payment_recorded` carries a `method` and no payer, and the mixed case — part to
  LuxMed by transfer, part on the patient's card — was not fully expressible. v2's
  `optional:` would make it expressible (F3), and whether the event should carry a
  payer is `DEC-05`'s owner's question. The port leaves the event as v1 had it.

  **`C-30` meant two different things and now does not.** The source model notices
  that one command labels both *close without payment* and *close commercially*,
  and leaves it unresolved. Two facts, two events, because a log that cannot tell a
  paid visit from an unpaid one is a log nobody can settle a day from.

  ## Two questions the port found (v2 §16, F1 and F2)

  **Where the total comes from (F1).** v1 said the amount "is computed from the lines
  already added, so the caller does not supply it". A pure decision cannot do that:
  service lines carry no price and nothing else carries an amount. So
  `hand_over_visit` carries the `total`, supplied by the application. The model's
  owner has to decide.

  **Which day a correction belongs to (F2).** v1 said the business date is "stamped
  by the system" and also that it is "the day it belongs to". Stamping the dispatch
  time would reproduce the incumbent's defect, so the decision takes the day of the
  handover from the state. A correction before any handover therefore has no day,
  and dispatch refuses the event it would decide; that too is the owner's question.

  ## The handoff, which is the weakest thing here

  `visit_handed_over` is `DEC-18`: the specialist marks the visit ready to charge,
  and that freezes everything price-bearing. It is `origin: appunite`, it
  contradicts a recorded client preference, and `U-09` goes further — nobody asked
  for the gate, every version of it was ours, and a physiotherapist said the status
  was unnecessary. `H177` in the Rehmed material makes the handoff a conditional
  command and moves the price freeze to settlement, which contradicts `DEC-18`
  again; it waits on the client, and the port carries the event as it stands.

  It is declared because without it there is no moment at which the amount becomes
  final, and the freeze rule has nothing to hang on. **If it becomes a warning
  rather than a gate, this process needs an earlier opening fact that this contract
  does not have** — the natural one is the treatment starting, and that belongs to
  `:clinical_visit`, so it could not be borrowed.

  ## No promise

  Nothing here has a stated time. The one promise anybody described is that a
  mid-visit addition reaches the desk at once, before the patient does — a moment,
  not an interval, answered by `DEC-17` with a push over sockets, which leaves no
  window to budget for. Writing `within: {30, :second}` would invent a number
  nobody said and turn a transport guarantee into an assertion about latency.

  What is verified is the shape: reconciled before closed, three ways to end
  including two bad ones, and whether the correction path is ever traversed — the
  known defect being that corrections attribute to the day they were entered rather
  than the day they belong to, which is why closed days drift.
  """

  use EhOsContract.Next.Contract, domain: Rehmed.Domain, context: :settlement

  aggregate :visit_settlement, "Rozliczenie wizyty" do
    identity :visit_id

    state do
      field :total, :money, optional: true
      field :payments, {:list, :money}, default: []
      field :handed_over_on, :date, optional: true
    end

    # `AGG-03` invariant 1, the one this contract was written for. The failure on
    # record is that split payments flip sign in the incumbent.
    invariant :payment_lines_sum_to_total, "Linie płatności sumują się do wartości rozliczenia",
      source: "W1 02:02:07; AGG-03 niezmiennik 1"

    # The commands are read off the event model's command catalogue
    # (`2-Solution/10-event-model.md` §4) rather than invented here. The actor
    # column there is what `by:` says: `A-02` is reception, `A-03` the specialist.

    # Refusable in the catalogue because the visit may already be settled; nothing
    # here declares that refusal, and the port adds none.
    command :add_service_line, "Dodanie usługi do rozliczenia wizyty",
      by: :specialist,
      emits: :service_line_added,
      source: "Event model §4, C-23, aktor A-03; W2 00:51:18" do
      field :service_id, :id
    end

    # The catalogue's own gloss is "one act by the specialist that hands the visit to
    # the desk", which is this event's label almost word for word.
    command :hand_over_visit, "Oznaczenie wizyty jako wykonanej",
      by: :specialist,
      emits: :visit_handed_over,
      source: "Event model §4, C-68, aktor A-03; Appunite 2026-08-17" do
      # F1: supplied with the command, since no decision can compute it.
      field :total, :money
    end

    command :record_payment, "Przyjęcie płatności za wizytę",
      by: :reception,
      emits: :payment_recorded,
      source: "Event model §4, C-31, aktor A-02; ESB L8" do
      field :method, :payment_method
      field :amount, :money
    end

    # `C-30` produces `E-53 / E-56`: both endings are this command's.
    command :close_settlement, "Zamknięcie rozliczenia wizyty",
      by: :reception,
      emits: [:visit_closed_commercially, :visit_closed_without_payment],
      rejects: :payment_lines_sum_to_total,
      source: "Event model §4, C-30, aktor A-02; H28"

    # `status: open` in the catalogue: the command is agreed, what may be corrected
    # is not.
    command :book_correction, "Zaksięgowanie korekty rozliczenia",
      by: :reception,
      emits: :settlement_corrected,
      source: "Event model §4, C-46, aktor A-02; process 10" do
      field :delta, :money
    end

    # Charging gates payment: an amount has to exist before it can be tendered.
    # Nothing is ordered inside either stage.
    stage :charging do
      # `E-45`, and the one write a specialist may not defer: adding a service
      # changes the price *and* the duration, and the patient does not leave the
      # room until it is confirmed. No amount: the fact is that a service joined.
      # The same service may be added twice, two of one treatment in one visit.
      event :service_line_added, "Dodano usługę do rozliczenia wizyty" do
        field :service_id, :id
      end

      # `E-115` / `DEC-18`, the transfer of authority over the price. `total` is
      # here because this is the moment the amount becomes final.
      event :visit_handed_over, "Wizyta oznaczona jako wykonana i gotowa do rozliczenia" do
        field :total, :money
      end
    end

    # A correction after a close is a real path and lives in the same stage as the
    # close it corrects: ordering it would claim corrections come last, and the whole
    # defect is that they do not land where they should.
    stage :payment do
      # `E-55`. Cash, card, transfer or a voucher; a split across methods is allowed
      # and is where the incumbent flips the sign.
      event :payment_recorded, "Pacjent opłacił wizytę" do
        field :method, :payment_method
        field :amount, :money
      end

      event :visit_closed_commercially, "Recepcja zamknęła wizytę", terminal: true

      # The other meaning `C-30` used to carry. A real ending and a bad one: `P-08`
      # exists precisely to notice it.
      event :visit_closed_without_payment, "Zamknięto wizytę bez płatności", terminal: true

      # `E-84`, and the payload is the shape of the known defect. A correction
      # carries the day it *belongs to*; the incumbent attributes it to the day it
      # was entered, so closed days drift silently. `delta` may be negative, so a
      # refund needs no separate event.
      event :settlement_corrected, "Zaksięgowano korektę rozliczenia" do
        field :delta, :money
        field :business_date, :date
      end
    end
  end

  # The same key as `:clinical_visit`, and deliberately a different process.
  # `DEC-18` made documentation and settlement independent and concurrent — the
  # specialist writes while reception settles — so no promise crosses them.
  process :visit_settlement, "Rozliczenie wizyty" do
    correlate :visit_id
    stage :charging
    stage :payment
  end

  # The numbers are the client's own, from the case where an unpaid penalty is
  # collected with the next visit: pay 200 zł at once, not 150
  # (VLW 00:19:58). A 150 zł visit plus a 50 zł penalty is 200 zł.
  scenario "wizyta 150 zł i kara 50 zł, zapłacone 200 zł — rozliczenie się zamyka" do
    given :visit_handed_over, %{total: 20_000}
    given :payment_recorded, %{method: :card, amount: 20_000}
    command :close_settlement
    expect :visit_closed_commercially
  end

  # The same money arriving as two lines: the case the incumbent gets wrong, written
  # as a case that passes.
  scenario "ta sama kwota w dwóch liniach — split jest poprawny, nie defektem" do
    given :visit_handed_over, %{total: 20_000}
    given :payment_recorded, %{method: :card, amount: 15_000}
    given :payment_recorded, %{method: :cash, amount: 5_000}
    command :close_settlement
    expect :visit_closed_commercially
  end

  scenario "zapłacone 150 zł przy należnych 200 — rozliczenie odrzucone" do
    given :visit_handed_over, %{total: 20_000}
    given :payment_recorded, %{method: :card, amount: 15_000}
    command :close_settlement
    rejected :payment_lines_sum_to_total
  end

  scenario "nic nie zapłacono — wizyta zamyka się bez płatności, i to jest legalne" do
    given :visit_handed_over, %{total: 20_000}
    command :close_settlement
    expect :visit_closed_without_payment
  end
end
