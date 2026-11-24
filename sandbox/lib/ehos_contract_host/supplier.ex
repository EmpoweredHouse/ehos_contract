defmodule EhosContractHost.Supplier do
  @moduledoc """
  The host's `EhosContract.Supplier`. A host configures one, and the sandbox holds
  several domains, so each request goes to the stand-in of the domain whose contract
  asks: today only the library's tariff. A domain with none here is not this
  host's to answer.
  """

  use Boundary, top_level?: true, deps: [EhosContract, Lending], exports: []

  @behaviour EhosContract.Supplier

  @suppliers %{Lending.Domain => Lending.Supplier}

  @impl true
  def supply(actor, %{contract: contract} = request) do
    case Map.fetch(@suppliers, EhosContract.Model.fetch(contract).domain) do
      {:ok, supplier} -> supplier.supply(actor, request)
      :error -> {:error, :not_supplied_here}
    end
  end
end
