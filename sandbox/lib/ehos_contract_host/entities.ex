defmodule EhosContractHost.Entities do
  @moduledoc """
  The host's `EhosContract.Entities`. A host configures one, and the sandbox holds
  several domains, so each read goes to the stand-in of the domain that declares the
  entity: today only the library's card system.
  """

  use Boundary, top_level?: true, deps: [EhosContract, Lending], exports: []

  @behaviour EhosContract.Entities

  @sources %{Lending.Domain => Lending.Entities}

  @impl true
  def fetch(actor, domain, entity, id) do
    case Map.fetch(@sources, domain) do
      {:ok, source} ->
        source.fetch(actor, domain, entity, id)

      # Said by name, rather than a FunctionClauseError whose log would print the actor.
      :error ->
        raise ArgumentError,
              "#{inspect(__MODULE__)} has no entity source for #{inspect(domain)}: add one here"
    end
  end
end
