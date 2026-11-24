defmodule UniversalityGate.Episode do
  @moduledoc """
  **Invented, like the whole of `UniversalityGate.TreatmentEpisode`.**

  The decider of its `:episode` aggregate (v2 plan, E5): v1's decision function
  written as an implementation. The decision is the same, but for an active payer that
  names no scope, which is refused rather than confirmed without one. What changed is its
  shape: the command carries the payer registry's answer instead of a map of
  inputs; the events are the contract's structs rather than names with maps, so
  `emit/1` checks at compile time that `qualify_referral` may produce them; and the
  refusal names the contract's invariant rather than an atom of its own.

  The registry's answer still arrives as input: a decision that called the registry
  could not tell "the payer refused" from "the registry is not answering". When it
  was checked is the command's time, which dispatch sets.
  """

  use UniversalityGate.TreatmentEpisode, aggregate: :episode

  alias EhosContract.Meta

  @impl true
  def qualify_referral(%QualifyReferral{identity_confirmed: false}, _state),
    do: reject(:treatment_starts_only_on_confirmed_eligibility)

  # An active payer that names no scope has confirmed nothing a treatment could start
  # on, and the confirmation it would emit requires one: found by the property tests
  # (plan DD, PC2, #266), where the decision emitted it without.
  def qualify_referral(%QualifyReferral{payer_status: :active, payer_scope: nil}, _state),
    do: reject(:treatment_starts_only_on_confirmed_eligibility)

  # `emit/1` takes literals, so what both outcomes share is written in each.
  def qualify_referral(%QualifyReferral{episode_id: id, __meta__: meta} = command, _state) do
    checked_at = checked_at(meta)

    case command.payer_status do
      :active ->
        emit([
          %PatientIdentityConfirmed{
            episode_id: id,
            patient_id: command.patient_id,
            document_type: :id_card
          },
          %PayerEligibilityChecked{episode_id: id, checked_at: checked_at},
          %PayerEligibilityConfirmed{episode_id: id, scope: command.payer_scope}
        ])

      status ->
        emit([
          %PatientIdentityConfirmed{
            episode_id: id,
            patient_id: command.patient_id,
            document_type: :id_card
          },
          %PayerEligibilityChecked{episode_id: id, checked_at: checked_at},
          %PayerEligibilityDenied{episode_id: id, reason: "eligibility #{status}"}
        ])
    end
  end

  defp checked_at(%Meta{occurred_at: %DateTime{} = at}), do: at

  defp checked_at(_no_time),
    do: raise(ArgumentError, "a command carries the time dispatch sets, and this one has none")
end
