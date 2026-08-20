defmodule Rehmed.Contracts.ClinicalVisit do
  @moduledoc """
  A visit from the moment the patient enters the room to the statutory report:
  **four facts, two promises and one dependency.**

      Pacjent wszedł do gabinetu
        → Pacjent wyszedł z gabinetu
            → Zamknięto wizytę przez specjalistę      (natychmiast — to jest sygnał dla recepcji)
            → Utworzono zadanie: dokumentacja do uzupełnienia
                → Wysłano zgłoszenie zdarzenia medycznego do P1

  | Assertion | Window | Where the number comes from |
  | --- | --- | --- |
  | reported, or somebody is chasing it | `{24, :hour}` | client decision 2026-08-13, deliberately inside the statutory window |
  | reported, or the service is not reportable | `{2, :day}` | Dz.U. 2025 poz. 866 — 48 hours, as the clinic says it |

  They nest on purpose: an escalation that fires at hour 48 is a post-mortem, not
  a warning.

  Distilled from `2-Solution/` in the Rehmed engagement repository via
  [`docs/rehmed-2026-08-18-distillation.md`](../../../docs/rehmed-2026-08-18-distillation.md),
  processes 2 and 3. Sources are cited as that repository cites them: `E-nn` for a
  board event, `AGG-nn` for an aggregate, `H-nn` for an open question, `W1`/`W2`/
  `VLW` plus a timestamp for a transcript.

  **Everything here is `status: open`.** Nothing in the source model has been
  confirmed by the client, and four of its 115 events are marked `observed`.

  ## How the close and the deadline work

  Corrected by the engagement lead on 2026-08-19, and it is what shapes both
  assertions:

  1. **The specialist marks the visit finished immediately.** That is what tells
     reception the patient can be settled; reception then opens the visit and reads
     whatever note is on it. The note needs no event of its own — the close is the
     signal.
  2. **The documentation is what gets deferred**, not the close. If the visit is
     not closed and the P1 forms are not filed, a task is raised for the specialist
     to come back to it.
  3. **48 hours is the statutory bound** for the documentation reaching the
     government API.

  **This settles `DEC-19` against us.** That proposal made ICD codes a hard
  requirement on the clinical close, contradicting the room's 2026-08-13 *remind,
  don't block*. Under the account above the close comes first and carries no codes,
  so this contract does not implement it. Recorded rather than quietly dropped.

  ## Why documentation and P1 are one process

  They have one instance key. `AGG-01` (booking), `AGG-02` (documentation),
  `AGG-03` (settlement) and `AGG-10` (the P1 report) are four aggregates in the
  source model and all four are identified by the visit. A `trace` may not span two
  processes, so declaring these as two would make the one assertion worth having
  unexpressible: from the end of the service to the statutory report crosses
  `AGG-02` into `AGG-10`.

  An aggregate boundary is a claim about what must stay consistent under a write.
  A process is a claim about a run. They are not the same question, and this is the
  first place in the repository where they visibly come apart.

  Settlement is not here. It shares the instance key and belongs by the same
  argument, but it is a different conversation with a different stakeholder —
  `Rehmed.Contracts.VisitSettlement`.

  ## What the payloads carry, and what they refuse to

  **This contract records that facts happened. It is not the medical record.** No
  ICD code, no interview text, no PESEL — and therefore not a single `:string`
  field, which is the type the retention check exists for. Polish medical
  documentation is retained for decades (the client's own recollection is *20 lat,
  czy ileś trzeba*, offered with visible uncertainty and never verified), and an
  append-only log carrying the clinical content would become medical documentation
  with a different lifecycle from the tables around it. The domain keeps the
  record; the log keeps the fact that it was written.

  Nothing carries who acted either. `actor` is a column of the log, so a payload
  field would be a second source of truth about one fact, and the two come apart
  exactly when an audit needs them. `AGG-02`'s invariant 3 — *only the specialist
  who delivered the visit may close it clinically* — is enforced where
  authorization lives.

  ## No cadence, no deadline, no rule

  **No `cadence`.** Every event here is fired by a person interacting with a
  screen. Forcing a cadence onto an event-driven process would make a
  calendar-shaped claim about work that arrives when patients do.

  **No `deadline`.** The two numbers are assertions between events. A process-level
  deadline would restate one of them in a declaration nothing reads yet.

  **No `rule`, and therefore no `example`.** A rule points at one pure function and
  Rehmed has no domain code here. The candidate is real and waits for an
  implementation: whether a service is reportable follows from the provider
  registration, one flag on the catalogue (`H21`, `DEC-20`).

  ## Two things this contract cannot say

  **A contested assertion cannot be marked as such.** `unverified` covers `cadence`
  and `deadline` only, so `PNS.Conformance.verified_declarations/1` cannot exclude
  a `trace` the process owner has not confirmed. Both assertions below will count
  towards an evidence report. Here that is defensible — one number is statutory and
  the other is a client decision with a date — but the mechanism would not have
  stopped a worse pair.

  **An assertion measures from when the log was told, not from when it happened.**
  The window runs from the entry for `visit_completed`. The anchor is the best
  available: departure from the room is recorded in the room, in real time, on the
  panel the specialist already has open.

  ## How this file was actually built, kept because it is evidence about the method

  Five rounds of correction, and **the module review found none of them**. Four
  came from reading a rendered diagram; two of those from somebody who had not
  written the contract.

  | # | What was wrong | Found by |
  | --- | --- | --- |
  | 1 | the close came after the work it closes, unstated | the diagram: eleven boxes, one arrow |
  | 2 | the in-room work preceded departure, unstated — and the visit had no beginning, `E-40` undeclared while `E-51` was | a reader asking what led into *Pacjent wyszedł z gabinetu* |
  | 3 | `E-42` sat beside the treatment as though it followed it; it is a **shortcut for the history**, and the note that does follow was `E-49`, missing | a reader saying the in-room order was wrong |
  | 4 | **six of the thirteen events were fields**, not facts | a reader saying *a note is not an action* |
  | 5 | the close is immediate; the 24 hours belonged to the chase, not to it | the engagement lead's account of how it works |

  Rounds 1–3 have the same shape and it is worth naming because it will recur:
  **fear of one false ordering claim produced no claim at all**, which is hard to
  see in a list of declarations and trivial to see in a drawing.

  Round 4 is the one that mattered most. Big Picture Event Storming produces a
  sticky for everything that *happens*; a contract needs the facts something
  *depends on*. The board was carried across without that filter, and the test now
  in `contract-distillation` came out of it:

  > **Does anything outside this document depend on it having happened?**

  Removed on that test: `history_taken`, `previous_note_copied`,
  `reception_note_written`, `treatment_performed`, `diagnosis_coded`,
  `icd9_supplement_recorded`. Thirteen events became seven.

  ## The limit that remains

  `stages` is a total order over phases, so `:start` and `:departure` are
  single-event lanes purely to say one follows the other. Only `:closing` holds two,
  and they are genuinely unordered — the task exists precisely when the close has
  not happened. Recorded in `PLAN.md` as a library finding; there is nothing to work
  around here.
  """

  use PNS.Contract

  # --- in the room: the visit starts and the patient leaves ---

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

  # **Immediate, and that is the point of it**: this is what tells reception the
  # patient can be settled. It carries no codes — see `DEC-19` in the moduledoc.
  event :visit_closed_clinically,
    label: "Zamknięto wizytę przez specjalistę",
    owner: Rehmed.VisitDocumentation,
    payload: %{visit_id: :id},
    process: :clinical_visit,
    stage: :closing

  # The fallback of the 24-hour assertion: within a day the medical event is
  # reported, **or** somebody has been told to finish the documentation. The
  # client's written requirement asks for a task on the managing person's list;
  # `P-23` makes it exist from booking rather than detecting an absence afterwards,
  # which is a better mechanism and does not change what this event is.
  #
  # Not terminal — the specialist comes back and files the forms, which is exactly
  # what the task is for. A run where neither this nor the report ever appears is
  # the failure `AGG-02` invariant 2a describes, *ona ma 16 wizyt niezakończonych*
  # (W1 02:20:04), and it surfaces as a violated assertion rather than as a state.
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
