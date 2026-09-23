defmodule Rehmed.Contracts.VisitSettlement do
  @moduledoc """
  The commercial side of one visit: what it costs, who pays, and the declaration
  that it is finished.

  Distilled from process 4 of
  [`docs/rehmed-2026-08-18-distillation.md`](../../../docs/rehmed-2026-08-18-distillation.md)
  (`AGG-03`, `E-45`, `E-55`, `E-56`, `E-84`, `DEC-05`, `DEC-18`). **`status: open`
  throughout**, and one declaration below rests on the single most contested
  decision in the source model — see the handoff.

  ## Money, which is what this contract was written to confront

  The two Rehmed contracts before this one carried no amounts. Neither does
  TaxVision — `turnover_matched_with_invoice` pairs a turnover with an invoice by
  identifier and records no value, in an **accounting** product. Three contracts,
  zero amounts, and it never read as a gap.

  It stops working here, because `AGG-03`'s invariant is arithmetic: *payment lines
  sum to the settlement total*, and its failure is on record — split payments flip
  sign, so the daily report is wrong on exactly the days it matters.

  ### The type is `:integer`, in grosze, and that is not a workaround

  Minor units in an integer is the correct representation for money. Sums are
  exact, comparison is exact, and the alternative that looks friendlier — a decimal
  written as text — gives up arithmetic and, worse, lands in `:string`, which means
  *text a human typed* and is the one type the retention check reacts to. Hashing a
  price would satisfy that check and destroy the number.

  So the DSL is not missing a money type. **What it is missing is a way to say what
  a number counts**, and money is simply where that hurts first:

  | Field | Counts | Declared as |
  | --- | --- | --- |
  | `task_count` (TaxVision) | tasks | `:integer` |
  | `recipients` (TaxVision) | recipients | `:integer` |
  | `amount_minor` (here) | grosze | `:integer` |

  Nothing distinguishes them. A second contract writing **złote** into a field this
  one writes grosze into compiles, emits, and is added up wrong by a report, and no
  gate anywhere would notice — the same class of silent, plausible failure as the
  granularity limitation once recorded in `EhOsContract.Trace` and closed there 21 August 2026.

  The mitigation used here is a naming convention: every amount ends in `_minor`,
  so the unit is unmissable at the call site. **A convention is not a guarantee**,
  and calling it one would be the sort of claim this repository exists to detect in
  others.

  ### On adding a type, and why not yet

  If a type is ever added it is **`:decimal`, never `:money`.** `:decimal` is a
  shape — an exact base-10 number that must not be a float — and physics, tax
  rates and weights need it as much as prices do. `:money` names a thing an
  accountant recognises, which is this library knowing one client's domain: exactly
  the mistake `:period` was, removed after two days under the rule *if your type
  names a thing rather than a shape, it is `:id`*.

  The evidence bar should be the one that killed `:period` — counting. Across four
  contracts, the fields that would use `:decimal` are the **three** in this file.
  One domain, one contract. That is not enough, and the honest reading is that the
  reason to add it, when it comes, will be **exactness**, not money.

  ### Where an amount is carried, and where it is not

  Not every number belongs in a payload. The test applied here is whether **the
  number is the fact, or an attribute of the thing the fact is about**:

  | Event | Amount? | Why |
  | --- | --- | --- |
  | `payment_recorded` | **yes** | the fact *is* an amount tendered by a method |
  | `visit_handed_over` | **yes** | the fact is that this total is now final |
  | `settlement_corrected` | **yes** | a correction is a delta and nothing else |
  | `service_line_added` | no | the fact is that a service joined the settlement; its price is an attribute of that line |

  This is a judgement, not a rule the engine enforces, and it is worth saying that
  the engine never reads any of these values. `identity` and `instance` use fields
  as keys; `EhOsContract.Emitter` checks their shape; only `rule` and `example` read a number
  — and `example`'s `given:` is untyped domain state, so the money in the cases at
  the foot of this file is unconstrained by the closed set entirely.

  ## Two more things the material forced

  **An attribute that exists only sometimes cannot be a field.** A declared field
  must be present on every emission, so optionality is expressed by declaring
  another event. `Rehmed.Contracts.ClinicalVisit` hit this with the ICD-9
  supplement; here it bites harder. `DEC-05` says a settlement carries several
  payer lines, *each naming its payer* — and a privately paid line has no payer to
  name. There is no field shape that covers both, and the corpus never says what
  stands in for the payer when the patient pays. So `payment_recorded` carries a
  `method` and no payer, and the mixed case — part to LuxMed by transfer, part on
  the patient's card — is **not fully expressible here.** That is a gap in this
  contract, recorded rather than papered over with a nullable field the DSL would
  refuse anyway.

  **`C-30` meant two different things and now does not.** The source model notices
  that one command labels both *close without payment* and *close commercially*,
  and leaves it unresolved. Two facts, two events, because a log that cannot tell a
  paid visit from an unpaid one is a log nobody can settle a day from.

  ## The handoff, which is the weakest thing here

  `visit_handed_over` is `DEC-18`: the specialist marks the visit ready to charge,
  and that freezes everything price-bearing. It is `origin: appunite`, it
  contradicts a recorded client preference, and `U-09` goes further — nobody asked
  for the gate, every version of it was ours, and a physiotherapist said the status
  was unnecessary.

  It is declared because without it there is no moment at which the amount becomes
  final, and the freeze rule has nothing to hang on. **If it becomes a warning
  rather than a gate, this process needs an earlier opening fact that this contract
  does not have** — the natural one is the treatment starting, and that belongs to
  `:clinical_visit`, so it could not be borrowed. Third time in three contracts
  that a fact was needed by two runs and could belong to one.

  ## No assertion

  Nothing here has a stated time. The one promise anybody described is that a
  mid-visit addition reaches the desk *od razu, zanim dojdzie osoba* — a moment,
  not an interval, answered by `DEC-17` with a push over sockets, which leaves no
  window to budget for. Writing `within: {30, :second}` would invent a number
  nobody said and turn a transport guarantee into an assertion about latency.

  What is verified is the shape: reconciled before closed, three ways to end
  including two bad ones, and whether the correction path is ever traversed — the
  known defect being that corrections attribute to the day they were entered rather
  than the day they belong to, which is why closed days drift.
  """

  use EhOsContract.Contract

  # --- charging ---

  # `E-45`, and the one write a specialist may not defer: adding a service changes
  # the price *and* the duration, and the patient does not leave the room until it
  # is confirmed. The propagation of it to the desk is `DEC-17`'s push, not
  # anything declared here.
  #
  # No amount: the fact is that a service joined the settlement. What it costs is
  # an attribute of the line, and the line is a row in whatever holds settlements.
  event :service_line_added,
    label: "Dodano usługę do rozliczenia wizyty",
    owner: Rehmed.Settlement,
    payload: %{visit_id: :id, service_id: :id},
    # The same service may legitimately be added twice — two of the same treatment
    # in one visit — so the service cannot be part of the key on its own, and there
    # is nothing else here that would separate them. Left undeclared rather than
    # guessed: an asynchronous handler on an event without `identity` does not
    # compile, so this refuses to be forgotten at the point it would start to
    # matter.
    process: :visit_settlement,
    stage: :charging

  # `E-115` / `DEC-18`. The transfer of authority over the price — see the
  # moduledoc for how contested it is.
  #
  # `total_minor` is here because this is the moment the amount becomes final, and
  # a total that is only recoverable by re-adding the lines at read time is not a
  # frozen total.
  event :visit_handed_over,
    label: "Wizyta oznaczona jako wykonana i gotowa do rozliczenia",
    owner: Rehmed.Settlement,
    payload: %{visit_id: :id, total_minor: :integer},
    process: :visit_settlement,
    stage: :charging

  # --- payment ---

  # `E-55`. Cash, card, transfer or a voucher; a split across methods is allowed
  # and is where the incumbent flips the sign.
  event :payment_recorded,
    label: "Pacjent opłacił wizytę",
    owner: Rehmed.Settlement,
    payload: %{visit_id: :id, method: :enum, amount_minor: :integer},
    process: :visit_settlement,
    stage: :payment

  event :visit_closed_commercially,
    label: "Recepcja zamknęła wizytę",
    owner: Rehmed.Settlement,
    payload: %{visit_id: :id},
    process: :visit_settlement,
    stage: :payment,
    terminal: true

  # The other meaning `C-30` used to carry. A real ending and a bad one: `P-08`
  # exists precisely to notice it.
  event :visit_closed_without_payment,
    label: "Zamknięto wizytę bez płatności",
    owner: Rehmed.Settlement,
    payload: %{visit_id: :id},
    process: :visit_settlement,
    stage: :payment,
    terminal: true

  # `E-84`, and the payload is the shape of the known defect. A correction carries
  # the day it *belongs to*; today the incumbent attributes it to the day it was
  # entered, so closed days drift silently. Declaring `business_date` is what makes
  # the difference between the two expressible at all.
  #
  # `delta_minor` may be negative — `EhOsContract.Emitter` checks `is_integer/1`, so a
  # refund needs no separate event and no sign convention hidden in a name.
  event :settlement_corrected,
    label: "Zaksięgowano korektę rozliczenia",
    owner: Rehmed.Settlement,
    payload: %{visit_id: :id, delta_minor: :integer, business_date: :timestamp},
    process: :visit_settlement,
    stage: :payment

  # --- the process ---

  # Declared in stage 5.6 before the command catalogue had been read; the citation
  # was found afterwards and matches on both sides — `C-30` produces `E-53 / E-56`,
  # and this command's examples emit exactly `visit_closed_commercially` and
  # `visit_closed_without_payment`.
  command :close_settlement,
    label: "Zamknięcie rozliczenia wizyty",
    process: :visit_settlement,
    principals: [:human],
    payload: %{visit_id: :id},
    source: "Event model §4, C-30, aktor A-02; H28"

  # Four ways in, all four read off the event model's command catalogue
  # (`2-Solution/10-event-model.md` §4) rather than invented here. The actor column
  # there is what `principals:` says: `A-02` is reception, `A-03` the specialist,
  # and both are people — the catalogue has no command this process can issue to
  # itself.

  # Refusable in the catalogue because the visit may already be settled; that
  # refusal is a domain rule and not something a capability decides.
  command :add_service_line,
    label: "Dodanie usługi do rozliczenia wizyty",
    process: :visit_settlement,
    principals: [:human],
    payload: %{visit_id: :id, service_id: :id},
    source: "Event model §4, C-23, aktor A-03 (specjalista); W2 00:51:18"

  # The catalogue's own gloss is "one act by the specialist that hands the
  # visit to the desk", which is this event's label almost word for word. The
  # amount is computed from the lines already added, so the caller does not supply it.
  command :hand_over_visit,
    label: "Oznaczenie wizyty jako wykonanej",
    process: :visit_settlement,
    principals: [:human],
    payload: %{visit_id: :id},
    source: "Event model §4, C-68, aktor A-03; Appunite 2026-08-17"

  command :record_payment,
    label: "Przyjęcie płatności za wizytę",
    process: :visit_settlement,
    principals: [:human],
    payload: %{visit_id: :id, method: :enum, amount_minor: :integer},
    source: "Event model §4, C-31, aktor A-02 (recepcja); ESB L8"

  # `status: open` in the catalogue — the command is agreed,
  # what may be corrected is not. The business date is stamped by the system rather
  # than supplied, which is why it is on the event and not here.
  command :book_correction,
    label: "Zaksięgowanie korekty rozliczenia",
    process: :visit_settlement,
    principals: [:human],
    payload: %{visit_id: :id, delta_minor: :integer},
    source: "Event model §4, C-46, aktor A-02; process 10"

  process :visit_settlement,
    label: "Rozliczenie wizyty",
    # Charging gates payment: an amount has to exist before it can be tendered.
    # Nothing is ordered inside either stage — a correction after a close is a real
    # path and lives in the same stage as the close it corrects, because ordering
    # it would claim corrections come last, and the whole defect is that they do
    # not land where they should.
    stages: [:charging, :payment],
    # The same key as `:clinical_visit`, and deliberately a different process.
    # `DEC-18` made documentation and settlement independent and concurrent — the
    # specialist writes while reception settles — so no promise crosses them, and
    # two runs over one identity is what "concurrent and independent" looks like
    # when it is written down.
    instance: [:visit_id]

  # --- the rule, and the examples that pin it ---

  # An MFA rather than a capture: a capture would make this contract depend on the
  # domain at compile time, and handlers depend on the contract, so every change in
  # `Rehmed.Settlement` would recompile all of them. It also means `Rehmed.Contracts`
  # needs no boundary dependency on `Rehmed.Settlement` — the tuple is three atoms.
  rule :payment_lines_sum_to_the_total,
    label: "Linie płatności sumują się do wartości rozliczenia",
    function: {Rehmed.Settlement, :decide, 1},
    source: "W1 02:02:07 — split płatności odwraca znak; AGG-03 niezmiennik 1"

  # The numbers are the client's own, from the case where an unpaid penalty is
  # collected with the next visit: *musisz zapłacić od razu 200 zł, a nie 150*
  # (VLW 00:19:58). A 150 zł visit plus a 50 zł penalty is 200 zł, and it is the
  # same two-lines-on-one-settlement the mixed-payer case needs.
  example "wizyta 150 zł i kara 50 zł, zapłacone 200 zł — rozliczenie się zamyka",
    rule: :payment_lines_sum_to_the_total,
    given: %{
      total_minor: 20_000,
      payments: [%{method: "karta", amount_minor: 20_000}]
    },
    command: {:close_settlement, %{visit_id: "w-1"}},
    then: [:visit_closed_commercially]

  # The same money arriving as two lines. This is the case the incumbent gets
  # wrong, written as a case that passes.
  example "ta sama kwota w dwóch liniach — split jest poprawny, nie defektem",
    rule: :payment_lines_sum_to_the_total,
    given: %{
      total_minor: 20_000,
      payments: [
        %{method: "karta", amount_minor: 15_000},
        %{method: "gotówka", amount_minor: 5_000}
      ]
    },
    command: {:close_settlement, %{visit_id: "w-1"}},
    then: [:visit_closed_commercially]

  example "zapłacone 150 zł przy należnych 200 — rozliczenie odrzucone",
    rule: :payment_lines_sum_to_the_total,
    given: %{
      total_minor: 20_000,
      payments: [%{method: "karta", amount_minor: 15_000}]
    },
    command: {:close_settlement, %{visit_id: "w-1"}},
    rejected_with: :payment_lines_do_not_sum_to_total

  example "nic nie zapłacono — wizyta zamyka się bez płatności, i to jest legalne",
    rule: :payment_lines_sum_to_the_total,
    given: %{total_minor: 20_000, payments: []},
    command: {:close_settlement, %{visit_id: "w-1"}},
    then: [:visit_closed_without_payment]
end
