defmodule Taxvision.Adapters do
  @moduledoc "Adaptery do systemów zewnętrznych. Nazwane faktem biznesowym, nie vendorem."
  use Boundary, deps: [], exports: [RegistryLookup, RegistryLookup.Fake]
end

defmodule Taxvision.Adapters.RegistryLookup do
  @moduledoc """
  Rejestry publiczne za behaviourem (ADR §11-12, notatki §10-11).

  Trzy poziomy testów, z których trzeci zarabia na siebie: tak się dowiadujesz,
  że urząd zmienił API, przed klientem.

  | Poziom | Przeciw czemu | Kiedy |
  |---|---|---|
  | domenowy | niczemu — domena nie wie, że adapter istnieje | każdy przebieg |
  | integracyjny | fake implementujący ten behaviour | każde CI |
  | kontraktowy | prawdziwe środowisko testowe rejestru | harmonogram, nie commit |
  """

  @callback lookup(nip :: String.t()) ::
              {:ok, %{legal_form: String.t(), vat_status: String.t(), vies_status: String.t()}}
              | {:error, :unavailable}

  def lookup(nip), do: impl().lookup(nip)

  # Wybór implementacji przez konfigurację, nie przez flagę "test mode":
  # środowisko kontraktowe używa prawdziwego adaptera przeciw sandboxowi, co
  # jednym przełącznikiem się nie wyraża (notatki §11).
  defp impl do
    Application.get_env(:pns_prototype, __MODULE__, [])[:impl] || __MODULE__.Fake
  end
end

defmodule Taxvision.Adapters.RegistryLookup.Fake do
  @moduledoc """
  Fake, nie mock. Implementuje behaviour, więc kompilator pilnuje, że nie
  rozjedzie się z prawdziwym adapterem.

  Niedostępność rejestru **nie jest** negatywną weryfikacją — jest zawieszeniem.
  Zlanie tych dwóch stanów jest dokładnie tym błędem, przed którym ostrzega
  ADR §11-12: check przestaje umieć odróżnić "firma ma problem" od "urząd nie
  odpowiada".
  """

  @behaviour Taxvision.Adapters.RegistryLookup

  @impl true
  def lookup("unavailable"), do: {:error, :unavailable}

  def lookup(nip) do
    case Application.get_env(:pns_prototype, __MODULE__, [])[:responses] do
      %{^nip => response} -> response
      _ -> {:ok, %{legal_form: "JDG", vat_status: "czynny", vies_status: "aktywny"}}
    end
  end
end
