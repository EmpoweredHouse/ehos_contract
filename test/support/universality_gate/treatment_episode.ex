defmodule UniversalityGate.TreatmentEpisode do
  @moduledoc """
  # THIS CONTRACT IS INVENTED. IT IS NOT CLIENT MATERIAL.

  There is no workshop behind it, no process owner and no client. Rehmed starts on
  10 August and **there is no material from Rehmed yet** — if this file pretended
  to be client context, it would be exactly the kind of invented domain knowledge
  PNS exists to detect in others. Every event name, every deadline and every rule
  below comes from the author's imagination.

  This file **must not reach the context repository.** It lives in `test/support/`
  because it is an engine fixture, not a client tree.

  Its strings are English, unlike the TaxVision contract's. That is not an
  inconsistency: Polish belongs to what a real process owner reads as sentences,
  and this contract has no reader. It ships with the package, so it follows the
  package's language.

  ## So what is it for

  This is the universality gate from stage 1.2. It tests the **DSL's vocabulary,
  not knowledge of a domain**: whether `event`, `process`, `stage`, `trace`,
  `instance`, `identity`, `cadence`, `deadline`, `external`, `rule`, `example`,
  `retain` and `unverified` are enough to describe a process that has nothing to do
  with accounting.

  The criterion is hard and a test pins it: **zero new words in the DSL.** Until
  now the only evidence of universality read "one contract, one domain, one
  author", which was not evidence.

  Shapes chosen because TaxVision does not have them, or has them more weakly:

  | Shape | Where here |
  | --- | --- |
  | An event arriving without a command | `referral_received` — a referral arrives from outside |
  | The same event many times in one run | `session_completed`, once per visit |
  | Run identity from a single field | `instance: [:episode_id]` |
  | A process with no cadence | an episode starts with a referral, not with the calendar |

  The last row is the only place where something grated here, and it is a
  **missing applicability, not a missing word**: `cadence` is optional and an
  episode simply does not have one. Details at the process declaration.
  """

  use PNS.Contract

  # --- qualification ---

  event :referral_received,
    label: "Referral received",
    # An owner is named and the module does not exist — because there is no
    # implementation here. That is the same state in which
    # `bank_statement_received` names `Taxvision.Matching`: declared, unhandled.
    owner: UniversalityGate.Admissions,
    # An event arriving **without a command**: a referral comes from outside,
    # nobody here invoked it. Its payload therefore has to carry the run identity
    # on its own — there is no command to take it from.
    payload: %{episode_id: :id, patient_id: :id, referral_code: :id, received_at: :timestamp},
    process: :treatment_episode,
    stage: :qualification

  event :patient_identity_confirmed,
    label: "Patient identity confirmed",
    owner: UniversalityGate.Admissions,
    payload: %{episode_id: :id, patient_id: :id, document_type: :enum},
    process: :treatment_episode,
    stage: :qualification

  event :payer_eligibility_checked,
    label: "Eligibility checked against the payer's registry",
    owner: UniversalityGate.Admissions,
    depends_on: :payer_registry,
    payload: %{episode_id: :id, checked_at: :timestamp},
    process: :treatment_episode,
    stage: :qualification

  event :payer_eligibility_confirmed,
    label: "Eligibility confirmed",
    owner: UniversalityGate.Admissions,
    payload: %{episode_id: :id, scope: :enum},
    process: :treatment_episode,
    stage: :qualification

  event :payer_eligibility_denied,
    label: "Eligibility denied",
    owner: UniversalityGate.Admissions,
    payload: %{episode_id: :id, reason: :string},
    # The reason for a denial is a statement about a patient's health set against
    # the payer's decision. A hash goes to the log: proof that a denial happened
    # and which one, without keeping the content.
    retain: %{reason: :hash},
    # The same denial does not multiply facts, a different one does — exactly the
    # shape of `diff` in the registry divergence.
    identity: [:episode_id, :reason],
    process: :treatment_episode,
    stage: :qualification,
    terminal: true

  # --- plan ---

  event :treatment_plan_approved,
    label: "Treatment plan approved",
    owner: UniversalityGate.Planning,
    # `approved_by` stays in the payload and is **not** a duplicate of `actor` —
    # this is a boundary worth being able to draw. `actor` says who performed the
    # operation in the system; this is about who **stands behind the treatment
    # plan**, which is a fact about professional responsibility. A receptionist
    # entering a plan on a doctor's behalf is two different people in one event.
    #
    # Type `:id`, not `:string`: an identifier for a person, not their name typed
    # in by hand. That difference decides whether personal data reaches the log.
    payload: %{episode_id: :id, session_count: :integer, approved_by: :id},
    process: :treatment_episode,
    stage: :plan

  # --- delivery ---

  event :session_completed,
    label: "Session delivered",
    owner: UniversalityGate.Sessions,
    payload: %{episode_id: :id, session_no: :integer, performed_at: :timestamp},
    # **The same event many times in one run.** A fact's identity includes the
    # session number, a run's identity does not — so ten sessions are ten facts in
    # one episode, rather than ten episodes or one fact repeated. Without that
    # separation, one of the two would be inexpressible.
    identity: [:episode_id, :session_no],
    process: :treatment_episode,
    stage: :treatment

  event :session_missed,
    label: "Patient did not attend",
    owner: UniversalityGate.Sessions,
    payload: %{episode_id: :id, session_no: :integer, noted_at: :timestamp},
    identity: [:episode_id, :session_no],
    process: :treatment_episode,
    stage: :treatment

  # --- closing ---

  event :episode_closed,
    label: "Treatment episode closed",
    owner: UniversalityGate.Sessions,
    payload: %{episode_id: :id, outcome: :enum},
    process: :treatment_episode,
    stage: :closing,
    terminal: true

  event :episode_abandoned,
    label: "Treatment episode abandoned",
    owner: UniversalityGate.Sessions,
    payload: %{episode_id: :id, reason: :string},
    retain: %{reason: :hash},
    process: :treatment_episode,
    stage: :closing,
    terminal: true

  # --- the process ---

  process :treatment_episode,
    label: "Treatment episode: from referral to closing",
    stages: [:qualification, :plan, :treatment, :closing],
    # One run is one episode. A single field is enough, because an episode is
    # issued rather than composed out of a company and a period — and that is the
    # difference from TaxVision the DSL absorbed without a change.
    instance: [:episode_id],
    # **`cadence:` is deliberately absent, and that is a result of the gate rather
    # than an oversight.**
    #
    # Cadence answers "how often is an instance due", and the "never observed"
    # window is computed from it. An accounting month is due every month. A
    # treatment episode is never due — it starts when a referral arrives. No word
    # is missing here: the word is optional and simply does not apply.
    #
    # The consequence is real and belongs to notes §9 rather than to this file:
    # for event-driven processes the "never observed" window has nowhere to get
    # its length from and falls back to observed intervals.
    deadline: {30, :day},
    # Everything in this contract is invented, but `deadline` is the one
    # declaration that **pretends to be a number from reality** — the rest are
    # names and shapes. Without this marking, the evidence report would count an
    # invented deadline as a measured one.
    unverified: [:deadline]

  # --- assertions ---

  trace :referral_reaches_a_decision do
    from :referral_received
    eventually :payer_eligibility_confirmed, within: {3, :day}
    or_else :payer_eligibility_denied
  end

  trace :episode_reaches_an_end do
    from :treatment_plan_approved
    eventually :episode_closed, within: {90, :day}
    or_else :episode_abandoned
  end

  # --- an external dependency, named after the fact rather than the vendor ---

  external :payer_registry,
    label: "Payer registry: confirmation of eligibility for treatment",
    expected_latency: {5, :second},
    unavailable_looks_like: "no answer — eligibility undecided, not denied"

  # --- rule and examples (ADR §18) ---

  rule :treatment_starts_only_on_confirmed_eligibility,
    label: "Without a confirmed identity and eligibility, treatment does not start",
    function: {UniversalityGate.Eligibility, :decide, 1},
    source: "INVENTED. There is no workshop and no process owner — see the moduledoc."

  example "identity confirmed and eligibility active — qualification passes",
    rule: :treatment_starts_only_on_confirmed_eligibility,
    given: %{
      identity_confirmed: true,
      payer: %{status: "active", scope: "outpatient rehabilitation"}
    },
    command: {:qualify_referral, %{episode_id: "ep-1", patient_id: "p-1"}},
    then: [:payer_eligibility_confirmed]

  example "eligibility expired — a denial instead of qualification",
    rule: :treatment_starts_only_on_confirmed_eligibility,
    given: %{
      identity_confirmed: true,
      payer: %{status: "expired", scope: nil}
    },
    command: {:qualify_referral, %{episode_id: "ep-1", patient_id: "p-1"}},
    then: [:payer_eligibility_denied]

  example "identity unconfirmed — the command is rejected, the registry is not even asked",
    rule: :treatment_starts_only_on_confirmed_eligibility,
    given: %{
      identity_confirmed: false,
      payer: %{status: "active", scope: "outpatient rehabilitation"}
    },
    command: {:qualify_referral, %{episode_id: "ep-1", patient_id: "p-1"}},
    rejected_with: :patient_identity_not_confirmed
end
