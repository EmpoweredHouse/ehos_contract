defmodule UniversalityGate.Domain do
  @moduledoc """
  # THIS DOMAIN IS INVENTED. IT IS NOT CLIENT MATERIAL.

  The vocabulary `UniversalityGate.TreatmentEpisode` names (v2 plan, E4). Like
  the contract, everything here comes from the author's imagination, and its
  strings are English for the same reason: nobody reads it as a process owner.

  What moved here from the v1 contract: the external `payer_registry`, which v2
  declares once per application rather than per contract, and the role v1 wrote
  as the string `accountable: "Attending physician"`, which v2 makes an actor. The
  other actors are new, because v2 names who records a fact nobody commands (D6),
  and v1 had nowhere to say it.
  """

  use EhOsContract.Domain, name: :universality_gate, language: :en

  context :treatment, "Treatment episodes", subdomain: :core

  actor :attending_physician, :human, "Attending physician"
  actor :therapist, :human, "Therapist"
  actor :referral_intake, :system, "Referral intake"

  subject :patient, "Patient"

  value :payer_status, {:enum, [:active, :expired, :suspended]}
  value :outcome, {:enum, [:completed, :referred_on, :discontinued]}

  external :payer_registry, "Payer registry: confirmation of eligibility for treatment",
    direction: :outbound,
    expected_latency: {5, :second},
    unavailable_looks_like: "no answer — eligibility undecided, not denied"

  subdomain :core, "Core", type: :core
end
