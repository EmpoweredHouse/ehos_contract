defmodule UniversalityGate.TreatmentEpisode do
  @moduledoc """
  # THIS CONTRACT IS INVENTED. IT IS NOT CLIENT MATERIAL.

  The universality gate's v1 contract in the v2 DSL (v2 plan, E4). It translates and
  adds nothing, and what v1 said and v2 cannot say the same way is listed below
  rather than smoothed over. The v1 contract went with v1's tests (v2 plan, E11a),
  once each had a v2 test that took its behaviour over.

  The gate's shapes, the ones TaxVision does not have, all survive:

  | Shape | Here |
  | --- | --- |
  | An event arriving without a command | `referral_received`, `recorded_by: :referral_intake` (D6) |
  | The same event many times in one run | `session_completed`, many times in one episode's stream |
  | Run identity from a single field | `identity :episode_id`, and `correlate :episode_id` in `UniversalityGate.TreatmentEpisodeRun` |

  **What the translation changed, and why.**

  - *Who records a fact.* v1 has one command, `qualify_referral`; the other facts
    arrive. v2 refuses an event nothing can produce (A2), so each names who records
    it: the referral intake, the attending physician, the therapist — actors of
    `UniversalityGate.Domain`, invented with it.
  - *A fact's own identity is gone.* v1's `identity: [:episode_id, :session_no]`
    made ten sessions ten facts of one run. In v2 an episode is a stream, and ten
    `session_completed` in it are ten events without a key of their own.
  - *`retain: %{reason: :hash}` has no counterpart yet.* Crypto-shredding replaces
    it in E8, and marking `reason` personal needs the patient's identifier in the
    same event, which v1's payload does not carry. The two `reason` fields are plain
    `:string` until then, and that is a gap, not a decision.
  - *The rule becomes an invariant*, named as v1's rule was, and the examples
    become scenarios. v1's decision function received the payer registry's answer
    as input; here the command carries it. That function became this unit's decider
    in E5, `UniversalityGate.Episode`.
  - *`:enum` needs its members.* `document_type` has the one the fake produces;
    v1's `scope` was declared `:enum` and filled with a sentence, so it is a
    `:string`.
  - *The external and the accountable role moved to the domain*, where v2 keeps
    both.

  The run from referral to closing, its stages, promises and deadline are a process
  module's since plan DD, P2g (#228): `UniversalityGate.TreatmentEpisodeRun`.
  """

  use EhOsContract.Contract,
    domain: UniversalityGate.Domain,
    context: :treatment,
    id: "universality_gate.treatment_episode"

  aggregate :episode, "Treatment episode" do
    identity :episode_id

    invariant :treatment_starts_only_on_confirmed_eligibility,
              "Without a confirmed identity and eligibility, treatment does not start",
              source: "INVENTED. There is no workshop and no process owner — see the moduledoc."

    command :qualify_referral, "Qualify a referral",
      by: :attending_physician,
      emits: [
        :patient_identity_confirmed,
        :payer_eligibility_checked,
        :payer_eligibility_confirmed,
        :payer_eligibility_denied
      ],
      rejects: :treatment_starts_only_on_confirmed_eligibility do
      field :patient_id, :id, subject: :patient
      field :identity_confirmed, :boolean
      field :payer_status, :payer_status
      field :payer_scope, :string, optional: true
    end

    event :referral_received, "Referral received", recorded_by: :referral_intake do
      field :patient_id, :id, subject: :patient
      field :referral_code, :id
      field :received_at, :timestamp
    end

    event :patient_identity_confirmed, "Patient identity confirmed" do
      field :patient_id, :id, subject: :patient
      field :document_type, {:enum, [:id_card]}
    end

    event :payer_eligibility_checked, "Eligibility checked against the payer's registry",
      depends_on: :payer_registry do
      field :checked_at, :timestamp
    end

    event :payer_eligibility_confirmed, "Eligibility confirmed" do
      field :scope, :string
    end

    event :payer_eligibility_denied, "Eligibility denied" do
      field :reason, :string
    end

    event :treatment_plan_approved, "Treatment plan approved",
      recorded_by: :attending_physician do
      field :session_count, :integer
      field :approved_by, :id
    end

    event :session_completed, "Session delivered", recorded_by: :therapist do
      field :session_no, :integer
      field :performed_at, :timestamp
    end

    event :session_missed, "Patient did not attend", recorded_by: :therapist do
      field :session_no, :integer
      field :noted_at, :timestamp
    end

    event :episode_closed, "Treatment episode closed", recorded_by: :attending_physician do
      field :outcome, :outcome
    end

    event :episode_abandoned, "Treatment episode abandoned", recorded_by: :attending_physician do
      field :reason, :string
    end
  end

  scenario "identity confirmed and eligibility active — qualification passes" do
    given :referral_received, %{
      patient_id: "p-1",
      referral_code: "r-1",
      received_at: "2026-09-01T08:00:00Z"
    }

    command :qualify_referral, %{
      patient_id: "p-1",
      identity_confirmed: true,
      payer_status: :active,
      payer_scope: "outpatient rehabilitation"
    }

    expect :patient_identity_confirmed
    expect :payer_eligibility_checked
    expect :payer_eligibility_confirmed
  end

  scenario "eligibility expired — a denial instead of qualification" do
    given :referral_received, %{
      patient_id: "p-1",
      referral_code: "r-1",
      received_at: "2026-09-01T08:00:00Z"
    }

    command :qualify_referral, %{
      patient_id: "p-1",
      identity_confirmed: true,
      payer_status: :expired
    }

    expect :patient_identity_confirmed
    expect :payer_eligibility_checked
    expect :payer_eligibility_denied
  end

  scenario "identity unconfirmed — the command is rejected, the registry is not even asked" do
    given :referral_received, %{
      patient_id: "p-1",
      referral_code: "r-1",
      received_at: "2026-09-01T08:00:00Z"
    }

    command :qualify_referral, %{
      patient_id: "p-1",
      identity_confirmed: false,
      payer_status: :active
    }

    rejected :treatment_starts_only_on_confirmed_eligibility
  end
end
