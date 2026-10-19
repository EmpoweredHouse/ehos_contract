defmodule EhOsContractHost.Supplier do
  @moduledoc """
  The host's `EhOsContract.Supplier`. A host configures one, and the sandbox holds
  several domains, so each request goes to the stand-in of the domain whose contract
  asks: the library's tariff, the clinic's systems. A domain with none here is not this
  host's to answer.
  """

  use Boundary, top_level?: true, deps: [EhOsContract, Lending, Rehmed], exports: []

  @behaviour EhOsContract.Supplier

  @suppliers %{Lending.Domain => Lending.Supplier, Rehmed.Domain => Rehmed.Supplier}

  @impl true
  def supply(actor, %{contract: contract} = request) do
    case Map.fetch(@suppliers, EhOsContract.Model.fetch(contract).domain) do
      {:ok, supplier} -> supplier.supply(actor, request)
      :error -> {:error, :not_supplied_here}
    end
  end
end
