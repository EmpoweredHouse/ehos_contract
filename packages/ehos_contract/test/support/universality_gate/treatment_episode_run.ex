defmodule UniversalityGate.TreatmentEpisodeRun do
  @moduledoc """
  # THIS PROCESS IS INVENTED. IT IS NOT CLIENT MATERIAL.

  The universality gate's run, from a referral to the episode's closing, over the
  events of `UniversalityGate.TreatmentEpisode`, in v1's stages and with v1's two
  promises. Until plan DD, P2g (#228) it was `:treatment_episode` inside the contract.
  """

  use EhosContract.Process,
    id: "universality_gate.treatment_episode_run",
    domain: UniversalityGate.Domain,
    label: "Treatment episode: from referral to closing",
    accountable: :attending_physician

  correlate :episode_id

  stage :qualification,
    include: [
      {UniversalityGate.TreatmentEpisode,
       [
         :referral_received,
         :patient_identity_confirmed,
         :payer_eligibility_checked,
         :payer_eligibility_confirmed,
         :payer_eligibility_denied
       ]}
    ]

  stage :plan, include: [{UniversalityGate.TreatmentEpisode, :treatment_plan_approved}]

  stage :treatment,
    include: [{UniversalityGate.TreatmentEpisode, [:session_completed, :session_missed]}]

  stage :closing,
    include: [{UniversalityGate.TreatmentEpisode, [:episode_closed, :episode_abandoned]}]

  ends_on [:payer_eligibility_denied, :episode_closed, :episode_abandoned]

  # Everything here is invented, and the deadline is the one declaration that
  # pretends to be a number from reality; unverified, so no report counts it.
  deadline {30, :day}, unverified: true

  promise :referral_reaches_a_decision do
    from :referral_received
    eventually :payer_eligibility_confirmed
    within {3, :day}
    or_else :payer_eligibility_denied
  end

  promise :episode_reaches_an_end do
    from :treatment_plan_approved
    eventually :episode_closed
    within {90, :day}
    or_else :episode_abandoned
  end
end
