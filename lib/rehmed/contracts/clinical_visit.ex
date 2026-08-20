defmodule Rehmed.Contracts.ClinicalVisit do
  @moduledoc """
  A visit from the moment the patient enters the room to the statutory report —
  delivery, documentation, the specialist's clinical close, and the medical event
  reaching the national registry.

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

  ## Six stages, and every one of them was added by a reader rather than by me

  Order is declared between stages and never inside one, so a stage list is the
  only ordering claim a contract makes — and this file has now got it wrong twice
  in the same direction, both times caught by somebody looking at the picture
  rather than at the module.

  | Round | What was missing | How it was found |
  | --- | --- | --- |
  | two stages | the clinical close came after the work it closes, unstated | the diagram had eleven boxes and one arrow |
  | three stages | the interview and the treatment precede the patient leaving, unstated; and **the start of the visit was not an event at all** | a reader asked why nothing led into *Pacjent wyszedł z gabinetu* |

  The pattern in both is the same and worth naming, because it will recur: fear of
  one **false** ordering claim produced **no** claim, and the two are hard to tell
  apart in a list of declarations and trivial to tell apart in a drawing.

  The boundaries now declared, and who says so:

  - `:start` → `:delivery` — nothing happens to the patient before they are in the
    room. Board lane 7, `E-40` before `E-41`.
  - `:delivery` → `:departure` — the interview, the copied note and the treatment
    happen with the patient present. Board order, and `10-event-model.md` states
    that board order is authoritative for sequence.
  - `:documentation` → `:closing` — a close comes after what it closes.
  - `:closing` → `:reporting` — the report fires on the **specialist's** close, and
    reception closing and dispatching while the specialist is still writing was
    rejected in the room: *to nie może tak być* (VLW).

  **One boundary is contested and is left standing so that it can be argued with.**
  `:departure` → `:documentation` claims the ICD coding happens after the patient
  leaves. The board sequences `E-44` **before** `E-51`, so as an account of intent
  it is wrong; the transcripts describe coding deferred under workload — *16 wizyt
  niezakończonych*, *zaległości z tego dnia* — so as an account of practice it is
  right. **That contradiction is the most consequential behavioural fact in this
  process and it is a question for the client, not a call for us.** It is in the
  workshop questions rather than resolved here.

  Nothing is ordered inside `:delivery` or `:documentation`, and that part is
  deliberate: an interview and a treatment are not sequenced against each other by
  anything on record, and an attempt to place the ICD codes before the close is
  precisely the contested proposal `DEC-19`. Backward-edge detection reads this
  list, so a sequence claimed here that the business does not make would produce
  findings about nothing.

  **And that is still the limit of what `stages` can express.** The real shape is a
  partial order and a stage list is a total order over phases, so anything mutually
  unordered has to share a lane — which is why three of these six stages hold a
  single event. The list alternates between moments and spans because that is the
  only way to say *these in any order, then this one*. Recorded in `PLAN.md` as a
  library finding; there is no workaround for it here.

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

  event :treatment_performed,
    label: "Wykonano zabieg",
    owner: Rehmed.VisitDocumentation,
    payload: %{visit_id: :id},
    process: :clinical_visit,
    stage: :delivery

  event :history_taken,
    label: "Zebrano wywiad pacjenta",
    owner: Rehmed.VisitDocumentation,
    payload: %{visit_id: :id},
    process: :clinical_visit,
    stage: :delivery

  # One of the two ways the note starts, and the only one the physiotherapists
  # were observed using as a shortcut (`E-42`). It is a separate fact rather than
  # a flag on `history_taken`, because a copied note and a fresh interview are
  # different things to a reader a year from now.
  event :previous_note_copied,
    label: "Powielono notatkę z poprzedniej wizyty",
    owner: Rehmed.VisitDocumentation,
    payload: %{visit_id: :id},
    process: :clinical_visit,
    stage: :delivery

  # `E-44`, observed. ICD-10 is the diagnosis, ICD-9 the performed procedure —
  # verified against the physiotherapists' chamber and NFZ on 2026-08-13, after
  # the corpus had them the other way round at one garbled point.
  #
  # The codes themselves are not in the payload; see the moduledoc. What follows
  # from that is `identity`: without the codes there is nothing that could tell a
  # correction apart from the original, so none is declared. That is not a hole
  # left open by accident — an asynchronous handler on an event without
  # `identity` does not compile, so the question has to be answered before anyone
  # can build the thing that would suffer from the wrong answer.
  event :diagnosis_coded,
    label: "Wybrano kody ICD-10 i ICD-9",
    owner: Rehmed.VisitDocumentation,
    payload: %{visit_id: :id},
    process: :clinical_visit,
    stage: :documentation

  # The escape hatch, and it is not optional. Sometimes no ICD-9 matches what was
  # delivered — *ten program nie przyszukuje fali uderzeniowej, więc wpisujemy
  # zabiegi fizjoterapeutyczne i ja do góry dopisuję* (W2 00:46:28). A gate with no
  # way through is what teaches people to work around the system, and the
  # specialists had already invented their own.
  #
  # A separate event rather than an extra field, because a declared field must be
  # present on every emission: a supplement that is usually absent cannot be a
  # field on `diagnosis_coded` without refusing the ordinary case.
  event :icd9_supplement_recorded,
    label: "Dopisano opis zabiegu, dla którego nie ma kodu ICD-9",
    owner: Rehmed.VisitDocumentation,
    payload: %{visit_id: :id},
    process: :clinical_visit,
    stage: :documentation

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
  event :documentation_overdue_task_created,
    label: "Utworzono zadanie: wizyta niezamknięta w terminie",
    owner: Rehmed.Tasks,
    payload: %{visit_id: :id},
    process: :clinical_visit,
    stage: :documentation

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
    stages: [:start, :delivery, :departure, :documentation, :closing, :reporting],
    # One run is one visit. The same key identifies four aggregates in the source
    # model, which is why this is one process — see the moduledoc.
    instance: [:visit_id]

  # --- the assertions ---

  # *After the patient leaves the room, within 24 hours the specialist closes the
  # visit — or a task appears saying it is outstanding.*
  #
  # The 24 hours are the client's own decision, taken 2026-08-13 and deliberately
  # inside the statutory 48 so that a working day of margin remains.
  #
  # `within` binding the fallback is the point here rather than a side effect. The
  # requirement as originally written raised the task at 48 hours, which is exactly
  # when the statutory deadline expires — a post-mortem, not a warning. A task that
  # arrives after the window it exists to protect satisfies nothing, and the
  # assertion says so.
  trace :documentation_closed_within_a_day do
    from :visit_completed
    eventually :visit_closed_clinically, within: {24, :hour}
    or_else :documentation_overdue_task_created
  end

  # *After the patient leaves the room, within two days the medical event reaches
  # the registry — or it is established that this service is not reportable.*
  #
  # Two days is statutory: transmit immediately and no later than 2 days from the
  # end of an ambulatory service, or from its start where it spans days.
  # Consolidated text Dz.U. 2025 poz. 866; the obligation has applied since
  # 1 July 2021. Verified against the regulation on 2026-08-13 and, at that point,
  # recorded nowhere in the engagement.
  #
  # **The anchor is the end of the service, not the clinical close, and the
  # difference is the whole value of this assertion.** The dispatch fires on the
  # close (`P-07`), and closes are deferred by days — which is what the sixteen
  # unclosed visits are. An assertion anchored where the dispatch happens would
  # measure how reliably we send and report green while the deadline is being
  # missed. It would be a false metric about the one obligation that carries a
  # legal consequence.
  #
  # There is deliberately no `p1_report_overdue` event. The state exists in the
  # source model — `Przeterminowane`, described there as the state nobody can see
  # today because nothing watches the deadline — and a violated assertion is
  # exactly how it becomes visible. Declaring an event for it would ask the domain
  # to detect what the engine is for.
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
