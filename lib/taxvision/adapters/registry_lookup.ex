defmodule Taxvision.Adapters do
  @moduledoc "Adapters for external systems. Named after the business fact, not the vendor."
  use Boundary, deps: [], exports: [RegistryLookup, RegistryLookup.Fake]
end

defmodule Taxvision.Adapters.RegistryLookup do
  @moduledoc """
  Public registries behind a behaviour (ADR §11-12, notes §10-11).

  Three levels of tests, of which the third pays for itself: that is how you find
  out the authority changed its API before the client does.

  | Level | Against what | When |
  |---|---|---|
  | domain | nothing — the domain does not know the adapter exists | every run |
  | integration | a fake implementing this behaviour | every CI run |
  | contract | the registry's real test environment | on a schedule, not per commit |
  """

  @callback lookup(nip :: String.t()) ::
              {:ok, %{legal_form: String.t(), vat_status: String.t(), vies_status: String.t()}}
              | {:error, :unavailable}

  @doc "Looks a company up in the public registries."
  @spec lookup(String.t()) :: {:ok, map()} | {:error, :unavailable}
  def lookup(nip), do: impl().lookup(nip)

  # The implementation is chosen by configuration rather than by a "test mode"
  # flag: the contract environment uses the real adapter against a sandbox, which
  # a single switch cannot express (notes §11).
  defp impl do
    Application.get_env(:pns_prototype, __MODULE__, [])[:impl] || __MODULE__.Fake
  end
end

defmodule Taxvision.Adapters.RegistryLookup.Fake do
  @moduledoc """
  A fake, not a mock. It implements the behaviour, so the compiler makes sure it
  cannot drift from the real adapter.

  A registry being unavailable is **not** a negative verification — it is a
  suspension. Merging those two states is exactly the mistake ADR §11-12 warns
  about: the check loses the ability to separate "the company has a problem" from
  "the authority is not answering".
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
