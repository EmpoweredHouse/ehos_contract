defmodule UniversalityGate.PayerRegistry do
  @moduledoc """
  **Wymyślone, tak jak cały `UniversalityGate.TreatmentEpisode`.**

  Behaviour plus fake, bez prawdziwej integracji — to jest cały zakres etapu
  1.2 po stronie zależności zewnętrznych. Nazwany faktem biznesowym
  („uprawnienie do świadczenia"), nie vendorem, bo `external :payer_registry`
  w kontrakcie ma znaczyć to samo za dwa lata, kiedy po drugiej stronie będzie
  inny system.
  """

  @callback check(patient_id :: String.t()) ::
              {:ok, %{status: String.t(), scope: String.t() | nil}} | {:error, :unavailable}

  def check(patient_id), do: impl().check(patient_id)

  defp impl do
    Application.get_env(:pns_prototype, __MODULE__, [])[:impl] || __MODULE__.Fake
  end
end

defmodule UniversalityGate.PayerRegistry.Fake do
  @moduledoc """
  Fake, nie mock. Niedostępność rejestru **nie jest** odmową uprawnienia — jest
  brakiem rozstrzygnięcia, dokładnie tak, jak mówi `unavailable_looks_like` w
  kontrakcie. Zlanie tych dwóch stanów odbiera pacjentowi świadczenie z powodu
  awarii cudzego serwera.
  """

  @behaviour UniversalityGate.PayerRegistry

  @impl true
  def check("unavailable"), do: {:error, :unavailable}

  def check(patient_id) do
    case Application.get_env(:pns_prototype, __MODULE__, [])[:responses] do
      %{^patient_id => response} -> response
      _ -> {:ok, %{status: "aktywne", scope: "rehabilitacja ambulatoryjna"}}
    end
  end
end
