defmodule UniversalityGate.Eligibility do
  @moduledoc """
  **Wymyślone, tak jak cały `UniversalityGate.TreatmentEpisode`.**

  Istnieje z jednego powodu: `rule` wskazuje MFA, a `mix pns.check` sprawdza, że
  ta funkcja istnieje. Bez niej reguły nie da się zadeklarować, a bez reguły nie
  da się sprawdzić bramy §18 na drugiej domenie — czyli połowa słownika
  zostałaby nieprzetestowana.

  To nie jest handler i handlera tu nie będzie: etap 1.2 to **kontrakt plus
  fake'i, zero implementacji**. Funkcja decyzyjna jest czysta i bezstanowa,
  a odpowiedź rejestru płatnika dostaje **na wejściu**, nie woła jej sama —
  inaczej nie umiałaby odróżnić „płatnik odmówił" od „rejestr nie odpowiada",
  a to dla świadczeniodawcy jest całe pytanie (ADR §11-12).
  """

  def decide(%{command: :qualify_referral} = input) do
    base = %{episode_id: input.episode_id}
    now = input[:checked_at] || "1970-01-01T00:00:00Z"

    if input.identity_confirmed do
      prefix = [
        PNS.event(
          :patient_identity_confirmed,
          Map.merge(base, %{patient_id: input.patient_id, document_type: "dowód"})
        ),
        PNS.event(:payer_eligibility_checked, Map.put(base, :checked_at, now))
      ]

      case input.payer do
        %{status: "aktywne", scope: scope} ->
          prefix ++ [PNS.event(:payer_eligibility_confirmed, Map.put(base, :scope, scope))]

        %{status: status} ->
          prefix ++ [PNS.event(:payer_eligibility_denied, Map.put(base, :reason, "uprawnienie #{status}"))]
      end
    else
      {:error, :patient_identity_not_confirmed}
    end
  end
end
