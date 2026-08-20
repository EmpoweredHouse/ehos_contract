defmodule Rehmed.Contracts.ClinicalVisit do
  @moduledoc """
  A visit from the moment the patient enters the room to the statutory report:
  four facts and two promises.

  Distilled from `2-Solution/` in the Rehmed engagement repository via
  [`docs/rehmed-2026-08-18-distillation.md`](../../../docs/rehmed-2026-08-18-distillation.md),
  processes 2 and 3. Sources are cited the way that repository cites them: `E-nn`
  for a board event, `AGG-nn` for an aggregate, `H-nn` for an open question,
  `W1`/`W2`/`VLW` plus a timestamp for a transcript. The distillation carries the
  full chain; this file cites the nearest link.

  **Everything here is `status: open`.** Nothing in the source model has been
  confirmed by the client, and four of its 115 events are marked `observed`.

  ## Why documentation and P1 are one process

  They have one instance key. `AGG-01` (booking), `AGG-02` (documentation),
  `AGG-03` (settlement) and `AGG-10` (the P1 report) are four aggregates in the
  source model and all four are identified by the visit. A `trace` may not span
  two processes — each process has its own run identity — so declaring these as
  two processes would make the one assertion worth having unexpressible: from the
  end of the service to the statutory report crosses `AGG-02` into `AGG-10`.

  An aggregate boundary is a claim about what must stay consistent under a write.
  A process is a claim about a run. They are not the same question, and this is
  the first place in the repository where they visibly come apart.

  Settlement is not here. It shares the instance key and belongs in this process
  by the same argument, but it is a different conversation with a different
  stakeholder, and the material behind it has open questions this one does not.

  ## Four stages and seven events, after twelve turned out to be five too many

  **The largest correction came last and it was not about order at all.** Reading
  the diagram, the engagement lead said the notes are not actions — they are
  fields on the visit that the specialist fills in. So are the ICD codes. And a
  treatment performed needs no event either: if the patient entered the room and
  left it, the treatment happened.

  He was right, and the mistake has a name. Big Picture Event Storming produces a
  sticky for everything that *happens*; a contract needs facts that something
  *depends on*. I carried the board's stickies across without applying that test,
  and six of the twelve events here were edits to one document wearing the
  costume of domain facts. Removed: `history_taken`, `previous_note_copied`,
  `reception_note_written`, `treatment_performed`, `diagnosis_coded`,
  `icd9_supplement_recorded`.

  The test worth keeping, because it is sharper than *is it stored in a field*
  — the codes are a field and so is the total on a settlement:

  > **Does anything outside this document depend on it having happened?**

  ## How the close and the deadline actually work

  Corrected by the engagement lead, and it changes both assertions:

  1. **The specialist marks the visit finished immediately.** That is what tells
     reception the patient can be settled — reception then opens the visit and
     reads whatever note is on it. The note needs no event of its own; the close
     is the signal.
  2. **The documentation is what gets deferred**, not the close. If the visit is
     not closed and the P1 forms are not filed, tasks are raised for the
     specialist to come back to it.
  3. **48 hours is the statutory bound** for the documentation reaching the
     government API — the same 2 days the regulation states, said the way the
     clinic says it.

  **This settles a contested proposal, and it settles it against us.** `DEC-19`
  proposed that ICD codes be *required* to close a visit clinically, contradicting
  the room's 2026-08-13 *remind, don't block*. Under the account above the close
  happens first and carries no codes, so `DEC-19` is not what this contract
  implements. Recorded rather than quietly dropped.

  It also resolves the boundary this file has been carrying as contested. The
  question was whether coding happens before or after the patient leaves; the
  answer is that coding is not an event, and the thing that follows departure is
  the close.

  ## The two assertions, and where each number comes from

  | | Window | Source |
  | --- | --- | --- |
  | reported, or somebody is chasing it | `{24, :hour}` | client decision 2026-08-13, deliberately inside the statutory window |
  | reported, or the service is not reportable | `{2, :day}` | Dz.U. 2025 poz. 866; 48 hours as the clinic says it |

  They nest on purpose, and the 24-hour one moved to a different subject than the
  version it replaces. It used to assert *the visit is closed within 24 hours*,
  which the correction above makes wrong — the close is immediate, and a day-long
  window on it would assert something nobody wants. Attached to the chase instead,
  the same number does the job the client's own reasoning gave it: the escalation
  has to fire **before** the statutory deadline, because a task raised at hour 48
  is a post-mortem rather than a warning.

  ## Stages

  `[:start, :departure, :closing, :reporting]`, and every boundary is stated by
  somebody: the patient leaves after entering; the close and the chasing task
  follow departure; the report follows the close — *to nie może tak być* was the
  room's answer to reception closing and dispatching while the specialist is still
  writing (VLW).

  Only `:closing` holds more than one event, and those two are genuinely
  unordered: the task exists precisely when the close has not happened.

  **The limit of `stages` still stands** and is now cheap rather than expensive: a
  stage list is a total order over phases, so `:start` and `:departure` are single-
  event lanes purely to say that one follows the other. Recorded in `PLAN.md`.

  ## What the payloads deliberately do not carry

  **This contract records that facts happened. It is not the medical record.**

  No ICD code, no interview text, no PESEL, no certificate body — and therefore
  not a single `:string` field, which is the type the retention check exists for.
  The reasoning is not squeamishness: Polish medical documentation is retained for
  decades (the client's own recollection is *20 lat, czy ileś trzeba*, offered with
  visible uncertainty and never verified), and an append-only event log that
  carried the clinical content would become medical documentation with a different
  lifecycle from the tables around it. The domain keeps the record; the log keeps
  the fact that it was written.

  What that costs is real and is the open question at the end of this file: whether
  a correction to a code is the same fact as the original cannot be answered from
  a payload that does not carry the code.

  Nothing carries who acted, either. `actor` is a column of the log, written by the
  engine and carried across job boundaries — a payload field would be a second
  source of truth about one fact, and the two come apart exactly when an audit
  needs them. So `AGG-02`'s invariant 3, *only the specialist who delivered the
  visit may close it clinically*, is enforced where authorization lives, not by a
  field here.

  ## No cadence, no deadline, no rule

  **No `cadence`.** Nothing in this process is due on a schedule. Every event is
  fired by a person interacting with a screen — the specialist writing, the
  patient leaving the room. Forcing a cadence onto an event-driven process would
  make a monthly-shaped claim about work that arrives when patients do.

  **No `deadline`.** The two numbers this process has are assertions between
  events, and they are below. A process-level deadline would restate one of them
  in a declaration that nothing reads yet.

  **No `rule` and no `example`.** A rule points at one pure function, and Rehmed
  has no domain code in this repository. Writing one to satisfy the DSL would
  invent the decision it claims to pin. The candidate is real and waits for an
  implementation: whether a service is reportable follows from the provider
  registration, one flag on the service catalogue (`H21`, `DEC-20`).

  ## Two things this contract cannot say, recorded rather than worked around

  **A contested assertion cannot be marked as such.** `unverified` covers
  `cadence` and `deadline` only, so `PNS.Conformance.verified_declarations/1` has
  no way to exclude a `trace` the process owner has not confirmed. Both assertions
  below will count towards an evidence report. For `medical_event_reported` that
  is defensible — the number is statutory, not ours. For `documentation_closed`
  it is a client decision with a date, which is the next best thing. But the
  mechanism would not have stopped a worse pair, and that is worth knowing before
  the first client sees a report.

  **An assertion measures from when we were told, not from when it happened.**
  The window runs from the log entry for `visit_completed`. If a visit is recorded
  late, the measurement is optimistic about the very failure this process is about.
  The anchor is the best available: departure from the room is recorded in the
  room, in real time, by the panel the specialist already has open.
  """

  use PNS.Contract

  # --- in the room: the visit starts, is delivered, and the patient leaves ---

  # `E-40`, and its absence was the hole a reader found in the diagram: the
  # contract had the **end** of the service and not its start, although the board
  # carries both and `AGG-01` names `E-27`, `E-40` and `E-51` as one family of
  # arrival-driven transitions.
  #
  # **Not the same fact as arriving at the clinic.** `E-27 Klient pojawił się na
  # wizycie` is the waiting room — reception's *czeka na kanapie*, read model
  # `R-03` — and `20-aggregates.md` warns in as many words that mixing a
  # physical-presence state with a workflow state is what the board's colour
  # palette got wrong. `E-27` belongs to the booking process, which nobody has
  # written yet; this is the one that starts the clinical work.
  #
  # It also matters statutorily, though not for Rehmed today: the regulation
  # counts the two days from the **end** of an ambulatory service, or **from its
  # start** where the service spans days. Without this fact the second reading
  # could not be expressed at all.
  event :visit_started,
    label: "Pacjent wszedł do gabinetu",
    owner: Rehmed.VisitDocumentation,
    payload: %{visit_id: :id},
    process: :clinical_visit,
    stage: :start

  # The anchor of both assertions. `E-51`: the patient leaves the room, which is
  # the end of the ambulatory service and therefore the moment the statutory clock
  # starts — see the process below.
  #
  # `service_id` is here and nowhere else in this contract. It is what decides
  # whether the reporting branch applies at all, so without it the graph shows a
  # branch nobody can explain.
  event :visit_completed,
    label: "Pacjent wyszedł z gabinetu",
    owner: Rehmed.VisitDocumentation,
    payload: %{visit_id: :id, service_id: :id},
    process: :clinical_visit,
    stage: :departure

  # **Its own stage since 2026-08-19**, and the reason is in the moduledoc: this is
  # the one ordering the material states and the contract was not claiming.
  event :visit_closed_clinically,
    label: "Zamknięto wizytę przez specjalistę",
    owner: Rehmed.VisitDocumentation,
    payload: %{visit_id: :id},
    process: :clinical_visit,
    stage: :closing

  # The fallback of the first assertion. The client's written requirement asks for
  # a task on the managing person's list when a visit has not been properly closed;
  # `P-23` makes the task exist from booking instead of detecting an absence
  # afterwards, which is a better mechanism and does not change what this event is.
  #
  # Not terminal: a visit that acquired an overdue task can still be closed, and
  # usually is. A run where neither this nor the close ever appears is the failure
  # `AGG-02` invariant 2a describes — *ona ma 16 wizyt niezakończonych* (W1
  # 02:20:04) — and it surfaces as an untraversed path rather than as a state.
  event :documentation_task_created,
    label: "Utworzono zadanie: dokumentacja wizyty do uzupełnienia",
    owner: Rehmed.Tasks,
    payload: %{visit_id: :id},
    process: :clinical_visit,
    stage: :closing

  # --- reporting: the statutory submission ---

  # The branch that ends the run without a report, and the reason it is an event
  # rather than silence. Most of what Rehmed does is never reported: massage is
  # named in the corpus as the negative example — *jak byśmy robili kamienicę od
  # masażu, to nie musimy tego robić* — and beauty, fitness and the stable carry no
  # obligation at all.
  #
  # Silence would make every non-medical visit look like an unfinished report.
  # Declaring the branch means the overlay can say something useful about it: if
  # this path is never traversed, either every service is flagged reportable or the
  # flag is not being read.
  event :p1_reporting_not_required,
    label: "Usługa nie podlega zgłoszeniu do rejestru zdarzeń medycznych",
    owner: Rehmed.Reporting,
    payload: %{visit_id: :id},
    process: :clinical_visit,
    stage: :reporting,
    terminal: true

  event :p1_report_sent,
    label: "Wysłano zgłoszenie zdarzenia medycznego do P1",
    owner: Rehmed.Reporting,
    depends_on: :medical_event_registry,
    payload: %{visit_id: :id},
    process: :clinical_visit,
    stage: :reporting,
    terminal: true

  # Feeds the retry queue rather than ending the run. What it cannot yet say is
  # whether a send that left the building was also accepted: everything the corpus
  # records about this integration is certificates loaded into the system and
  # visits reported on their basis. If the registry acknowledges a single event
  # distinguishably from a transport success, this splits in two and the retry
  # queue gets a different definition of done — `H64`, and the answer is in the
  # integration documentation, not in a workshop.
  event :p1_report_failed,
    label: "Zgłoszenie do P1 odrzucone albo nie doszło do rejestru",
    owner: Rehmed.Reporting,
    depends_on: :medical_event_registry,
    payload: %{visit_id: :id},
    process: :clinical_visit,
    stage: :reporting

  # --- the process ---

  process :clinical_visit,
    label: "Wizyta: wykonanie, dokumentacja i zgłoszenie zdarzenia medycznego",
    stages: [:start, :departure, :closing, :reporting],
    # One run is one visit. The same key identifies four aggregates in the source
    # model, which is why this is one process — see the moduledoc.
    instance: [:visit_id]

  # --- the assertions ---

  # *After the patient leaves the room, within 24 hours the medical event is
  # reported — or a task exists telling the specialist to finish it.*
  #
  # The 24 hours are the client's decision of 2026-08-13, taken deliberately inside
  # the statutory window. What changed on 2026-08-19 is what they are attached to.
  # They used to bound the **clinical close**, and that is wrong: the close is
  # immediate, because it is what tells reception the patient can be settled.
  # What is genuinely deferred is the documentation.
  #
  # `within` binding the fallback is the point rather than a side effect. The
  # requirement as first written raised the task at 48 hours, which is exactly when
  # the statutory deadline expires — a post-mortem, not a warning.
  trace :reported_or_chased_within_a_day do
    from :visit_completed
    eventually :p1_report_sent, within: {24, :hour}
    or_else :documentation_task_created
  end

  # *After the patient leaves the room, within two days the medical event reaches
  # the registry — or it is established that this service is not reportable.*
  #
  # Two days is statutory: transmit immediately and no later than 2 days from the
  # end of an ambulatory service, or from its start where it spans days.
  # Consolidated text Dz.U. 2025 poz. 866; the obligation has applied since
  # 1 July 2021. The clinic says the same number as 48 hours.
  #
  # **The anchor is the end of the service, not the close**, and that is the whole
  # value of this assertion. The specialist returns to an unfinished visit and files
  # the forms later; anchored on the close, the window would start when the work
  # resumed rather than when the obligation did.
  #
  # There is deliberately no `p1_report_overdue` event. The state exists in the
  # source model — `Przeterminowane`, described there as the one nobody can see
  # today because nothing watches the deadline — and a violated assertion is
  # exactly how it becomes visible.
  trace :medical_event_reported_within_statutory_window do
    from :visit_completed
    eventually :p1_report_sent, within: {2, :day}
    or_else :p1_reporting_not_required
  end

  # --- the external dependency ---

  # Named after the fact rather than the platform, so the declaration still means
  # the same thing if the platform is replaced.
  #
  # `expected_latency` is absent because nobody has measured it. What is on record
  # is that the integration is unreliable today — *cały czas źle funkcjonuje*,
  # specifically for physiotherapy codes — and whether that is the registry or the
  # incumbent's client is not established.
  #
  # The dependency earns the `depends_on` above for a reason the regulation itself
  # supplies: a system failure extends the deadline to 3 days from the moment it is
  # resolved. That is the only place in this engagement where the client's own
  # obligation comes with a written notion of what an outage does to it.
  #
  # It is not the same thing as suspension, and this contract does not pretend it
  # is. `depends_on` plus an observed outage yields `:suspended` — the run is not
  # judged. The regulation extends the window instead, so a run that stayed broken
  # past the extension would still be in breach while the engine reports it as
  # unjudged. Recorded here rather than approximated silently.
  external :medical_event_registry,
    label: "Krajowy rejestr zdarzeń medycznych (P1)",
    unavailable_looks_like:
      "odrzucenie zgłoszenia albo brak łączności z rejestrem; wygasły lub niewgrany certyfikat placówki"
end
