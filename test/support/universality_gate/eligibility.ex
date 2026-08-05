defmodule UniversalityGate.Eligibility do
  @moduledoc """
  **Invented, like the whole of `UniversalityGate.TreatmentEpisode`.**

  It exists for one reason: a `rule` names an MFA, and `mix pns.check` verifies
  that the function exists. Without it the rule cannot be declared, and without a
  rule the §18 gate cannot be exercised on a second domain — which would leave
  half the vocabulary untested.

  This is not a handler and there will not be one: stage 1.2 is **a contract plus
  fakes, zero implementation**. The decision function is pure and stateless, and it
  receives the payer registry's answer **as input** rather than calling it —
  otherwise it could not separate "the payer refused" from "the registry is not
  answering", and for a provider that is the whole question (ADR §11-12).
  """

  @doc "Decides whether a referral qualifies, given an already-fetched payer answer."
  @spec decide(map()) :: [PNS.Emission.t()] | {:error, atom()}
  def decide(%{command: :qualify_referral} = input) do
    base = %{episode_id: input.episode_id}
    now = input[:checked_at] || "1970-01-01T00:00:00Z"

    if input.identity_confirmed do
      prefix = [
        PNS.event(
          :patient_identity_confirmed,
          Map.merge(base, %{patient_id: input.patient_id, document_type: "id_card"})
        ),
        PNS.event(:payer_eligibility_checked, Map.put(base, :checked_at, now))
      ]

      case input.payer do
        %{status: "active", scope: scope} ->
          prefix ++ [PNS.event(:payer_eligibility_confirmed, Map.put(base, :scope, scope))]

        %{status: status} ->
          prefix ++
            [PNS.event(:payer_eligibility_denied, Map.put(base, :reason, "eligibility #{status}"))]
      end
    else
      {:error, :patient_identity_not_confirmed}
    end
  end
end
