defmodule Rehmed.Contracts.PayerSettlement do
  @moduledoc """
  The monthly settlement with an external payer: reconciling which delivered
  visits the payer owes for, and issuing the invoice.

  Distilled from process 5 of
  [`docs/rehmed-2026-08-18-distillation.md`](../../../docs/rehmed-2026-08-18-distillation.md)
  (`AGG-11`, `E-85`–`E-87`, `DEC-16`). **Everything is `status: open`**, and this
  is the thinnest material in the engagement: six events for a flow that decides
  whether a payer pays us, and a main source whose speaker mapping is unconfirmed.

  ## Read this one for what it could not say

  As test data for the library this contract is more useful than the clinical one,
  because it is where the DSL ran out. Four findings, all recorded in `PLAN.md` as
  library work rather than as notes about a clinic.

  ### 1. The promise that protects the money is per item, and `trace` is per run

  The invariant on record is: *every delivered payer-funded visit in a settlement
  period is either included in that period's invoice, or excluded with a stated
  reason.* Its failure costs money in both directions, and the client names both —
  *jeśli czegoś nie uwzględni to będziemy stratni, jeśli wyliczy za dużo to będzie
  problem z LuxMed.*

  That is a **quantifier over a set**, not *after A comes B*. A run here is one
  payer in one month and contains dozens of visits. An assertion anchored on a
  per-visit fact would open its window on the **first** occurrence in the run and
  be satisfied by **any** later match — so forty unsettled visits behind one
  settled one would report as satisfied.

  This was worse than a refusal, and is why finding 2 below still matters: as of
  21 August 2026, `EhOsContract.Trace` quantifies exactly this shape — see its moduledoc —
  so an assertion finer than its run is now evaluated per item rather than failing
  quietly towards good news. `EhOsContract.Check.assertions_finer_than_their_run/1` still
  flags it, now as "confirm the target events carry the item's identity fields
  too," not as a defect.

  That fixes finding 1 in isolation. It does not fix this contract: finding 2 is
  the reason the assertion still cannot be written here, quantification or not.

  ### 2. The fact that would anchor it belongs to another run

  The natural anchor is *the visit was delivered*. It belongs to `:clinical_visit`,
  whose instance is the visit — and an event names a single process, so it cannot
  also belong here. Two run identities, one fact, and the promise needs both.

  Merging the two processes is not the answer either: this run is a payer-month and
  that one is a visit, and one of them would stop being countable.

  ### 3. `instance` fields have to be knowable when the fact happens

  `E-85 Zarejestrowano wizytę w systemie płatnika` is deliberately absent below.
  It is real, load-bearing and happens **before delivery** — the payer requires the
  visit in their own system first. But this run is keyed by payer and settlement
  period, and at registration nobody knows which period the visit will settle in:
  it is booked against a horizon of two months, and `DEC-16` makes the settlement
  period a property of the invoice that eventually pays for it.

  So the event cannot carry this run's key at the moment it occurs. That is a
  general constraint the DSL does not state anywhere: `instance` is not just "the
  fields that group the run", it is "the fields knowable at emit time". TaxVision
  never surfaced it because an accounting month is known before any work in it.

  ### 4. A manual dependency has no observable outage

  `external` is declared below and **no event declares `depends_on` for it**, which
  looks like an omission and is not.

  There is no API. Registration and the settlement mark are a person retyping into
  the payer's own panel; `F-05` is a checklist with a human behind it. `depends_on`
  earns its place by producing `:suspended` when a dependency was **seen**
  unavailable inside an assertion window — and nothing here can see anything. The
  declaration is worth keeping because the dependency is real and the ACL exists
  because of it; wiring `depends_on` to it would promise a verdict that can never
  fire.

  ## What it does verify, and it is not nothing

  Order between reconciliation and invoicing, three ways the period ends including
  two bad ones, and — the useful one — whether the exclusion path is ever
  traversed. If a period is invoiced and no visit was ever excluded with a reason,
  either every delivered visit really was billable or nobody is running the
  completeness check. The client's own description says which is likelier: the
  monthly check looks for implausible values, not for completeness.

  ## No money in any payload

  `payer_invoice_issued` carries the invoice's identity and not its value. There is
  no type for a monetary amount in the closed set, and the two workarounds — minor
  units as `:integer`, or text — each give up something real. Rather than pick one
  inside a contract, the fact recorded here is that the invoice was issued; what it
  was worth belongs to whatever issues it.

  That dodge works because nothing here asserts a sum. It would not work for
  `AGG-03`, whose invariant is that payment lines add up to the total, and that is
  the shape the library will eventually have to answer for.

  ## No rule, no deadline

  As in `Rehmed.Contracts.ClinicalVisit`: a `rule` points at a pure function and
  Rehmed has no domain code here.

  One assertion was available and is deliberately not declared. `H38` records a
  contractual obligation to see a payer's patient **within 7 days** against a real
  queue of at least two months — which would be the sharpest assertion in the whole
  engagement if anyone had confirmed the obligation exists. Nobody has. And
  `unverified` covers `cadence` and `deadline` only, so there is no way to declare
  it and keep it out of the evidence report.

  **That is the second contract in a row where the missing `unverified` scope
  changed what could be written**, which moves it from an observation to a backlog
  item.
  """

  use EhOsContract.Contract

  # --- reconciliation ---

  # The load-bearing click. If it is not made, the payer simply does not pay —
  # rule 9 of the fourteen the source model lists as enforced by nothing but
  # somebody's memory.
  #
  # Corrected on the client side 2026-08-14: this happens at reception, per visit,
  # at the moment of settlement — not as a monthly sweep. The payer is already
  # known from the booking, so it is a step on a screen someone is already looking
  # at rather than something to remember from scratch. A step on the path cannot be
  # forgotten; a reminder can.
  event :visit_marked_settled_with_payer,
    label: "Oznaczono wizytę jako rozliczoną u płatnika",
    owner: Rehmed.PayerSettlement,
    payload: %{payer_id: :id, period_id: :id, visit_id: :id},
    # The same visit marked twice in the same period is one fact. Unlike
    # TaxVision's discrepancy, there is no content here that could make a second
    # occurrence a different fact.
    identity: [:payer_id, :period_id, :visit_id],
    process: :payer_settlement,
    stage: :reconciliation

  # The other half of the completeness invariant, and the half that makes it
  # checkable at all: a delivered visit that will not be invoiced has to say why.
  #
  # `reason` is the only human-typed text in either Rehmed contract, and it is
  # `:persist` on purpose. Hashing it would satisfy the retention check and destroy
  # the declaration — an exclusion whose reason nobody can read is an exclusion
  # without a reason, which is the state being replaced. It is accounting prose
  # about a visit, not clinical content.
  event :visit_excluded_from_invoice,
    label: "Wykluczono wizytę z rozliczenia okresu, z podanym powodem",
    owner: Rehmed.PayerSettlement,
    payload: %{payer_id: :id, period_id: :id, visit_id: :id, reason: :string},
    retain: %{reason: :persist},
    identity: [:payer_id, :period_id, :visit_id],
    process: :payer_settlement,
    stage: :reconciliation

  # Human-initiated and named as such: once a month the practice manager opens the
  # module, verifies the data, and only then issues. `C-49` moved from reception to
  # the manager on 2026-08-14, and `R-08` stopped being a report and became a
  # working screen with a verification step in it.
  event :payer_visits_reconciled,
    label: "Zweryfikowano dane do rozliczenia płatnika za okres",
    owner: Rehmed.PayerSettlement,
    payload: %{payer_id: :id, period_id: :id},
    process: :payer_settlement,
    stage: :reconciliation

  # --- invoicing ---

  event :payer_invoice_issued,
    label: "Wystawiono fakturę miesięczną dla płatnika",
    owner: Rehmed.PayerSettlement,
    payload: %{payer_id: :id, period_id: :id, invoice_id: :id},
    process: :payer_settlement,
    stage: :invoicing,
    terminal: true

  # A period that closes with nothing to bill is a legitimate ending and a
  # different one from an unfinished period. Without it, a payer with no patients
  # this month is indistinguishable from a payer nobody got round to — and those go
  # to different people.
  #
  # `origin: appunite`. Nobody described this case; it is the ending the state
  # machine needs to stop lying about the other one. Marked here rather than
  # smuggled in as though the corpus had it.
  event :payer_period_closed_without_invoice,
    label: "Zamknięto okres bez faktury — brak wizyt do rozliczenia",
    owner: Rehmed.PayerSettlement,
    payload: %{payer_id: :id, period_id: :id},
    process: :payer_settlement,
    stage: :invoicing,
    terminal: true

  # --- the process ---

  # `C-48` and `C-49` from the event model's command catalogue
  # (`2-Solution/10-event-model.md` §4). The other three ways into this process have
  # no command there and are deliberately not invented — see `PLAN.md`.

  # The catalogue's source note is the one that matters here:
  # the click is easy to miss in the payer's own window, and missing it is how a
  # visit goes unpaid.
  command :mark_settled_with_payer,
    label: "Oznaczenie wizyty jako rozliczonej u płatnika",
    process: :payer_settlement,
    principals: [:human],
    payload: %{payer_id: :id, period_id: :id, visit_id: :id},
    source: "Event model §4, C-48, aktor A-02; R2P 00:15:06"

  # The actor is `A-05`, the practice manager, not reception. The
  # catalogue is explicit that this is human-initiated once a month after the data
  # has been verified — which is why the invoice number is not an input.
  command :issue_payer_invoice,
    label: "Wystawienie faktury miesięcznej dla płatnika",
    process: :payer_settlement,
    principals: [:human],
    payload: %{payer_id: :id, period_id: :id},
    source: "Event model §4, C-49, aktor A-05 (menedżer); Domain-Discovery §1"

  process :payer_settlement,
    label: "Miesięczne rozliczenie z płatnikiem zewnętrznym",
    # Reconciliation gates invoicing, and that is the whole of the order claim.
    # Within reconciliation nothing is ordered: marking a visit settled happens at
    # the desk, visit by visit, all month, while the manager's verification happens
    # once at the end — two rhythms, no sequence between them.
    stages: [:reconciliation, :invoicing],
    # One run is one payer in one month. Three payers settle independently, and the
    # source model is explicit that they are three instances of one type rather
    # than three integrations — Enelmed and TuZdrowie work identically to LuxMed,
    # confirmed 2026-08-14.
    instance: [:payer_id, :period_id],
    # The second monthly process in this repository, and the first one that is
    # monthly for a commercial reason rather than a statutory one. Still nothing
    # reads it: the never-observed monitor was rejected on 6 August, so this
    # declaration reaches the report as a declaration and no further.
    cadence: {1, :month}

  # --- no assertions, and the moduledoc says why ---

  # --- the external dependency ---

  # Named after the fact rather than the vendor, and singular rather than three:
  # one policy with per-payer parameters, one alias table, one adapter with three
  # configurations.
  #
  # No `expected_latency`, because there is no call to time. No `depends_on`
  # anywhere, because an outage here is a person who did not retype something, and
  # nothing can observe that — see the moduledoc.
  external :payer_settlement_system,
    label: "System rozliczeniowy płatnika zewnętrznego (LuxMed, Enelmed, TuZdrowie)",
    unavailable_looks_like:
      "panel płatnika niedostępny albo wizyta nie została w nim odnotowana przez człowieka — czego nasz system nie widzi"
end
