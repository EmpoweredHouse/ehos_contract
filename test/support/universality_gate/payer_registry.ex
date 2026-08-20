defmodule UniversalityGate.PayerRegistry do
  @moduledoc """
  **Invented, like the whole of `UniversalityGate.TreatmentEpisode`.**

  A behaviour plus a fake, with no real integration — that is the entire scope of
  stage 1.2 on the external-dependency side. Named after the business fact
  ("eligibility for treatment") rather than after a vendor, because
  `external :payer_registry` in the contract has to mean the same thing in two
  years, when a different system is on the other side.
  """

  @callback check(patient_id :: String.t()) ::
              {:ok, %{status: String.t(), scope: String.t() | nil}} | {:error, :unavailable}

  @doc "Checks a patient's eligibility with the payer."
  @spec check(String.t()) :: {:ok, map()} | {:error, :unavailable}
  def check(patient_id), do: impl().check(patient_id)

  defp impl do
    Application.get_env(:pns, __MODULE__, [])[:impl] || __MODULE__.Fake
  end
end

defmodule UniversalityGate.PayerRegistry.Fake do
  @moduledoc """
  A fake, not a mock. The registry being unavailable is **not** a denial of
  eligibility — it is the absence of a decision, exactly as
  `unavailable_looks_like` says in the contract. Merging those two states denies a
  patient treatment because somebody else's server broke.
  """

  @behaviour UniversalityGate.PayerRegistry

  @impl true
  def check("unavailable"), do: {:error, :unavailable}

  def check(patient_id) do
    case Application.get_env(:pns, __MODULE__, [])[:responses] do
      %{^patient_id => response} -> response
      _ -> {:ok, %{status: "active", scope: "outpatient rehabilitation"}}
    end
  end
end
