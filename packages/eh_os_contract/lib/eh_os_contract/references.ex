defmodule EhOsContract.References do
  # What a field typed `{:id, name}` identifies (plan DD, L3 (#286)): an entity of the
  # domain, which the application keeps, or a unit of one of the domain's contracts,
  # which its events make. The model stores either as `type: :id, refers_to: name`
  # (plan EM2), so the codec, tags and typespecs see a plain `:id`, and the name is
  # resolved here, against the domain and its contracts.
  #
  # A name has to match exactly one: the compiler between modules refuses a reference
  # that matches none or several (X3), so the readers after it — `check`, the pages,
  # the graph — take `resolve/3`'s answer, and all of them read it from this one place.
  @moduledoc false

  @typedoc "What a name refers to: an entity of the domain, or a unit of a contract's model."
  @type referent :: {:entity, atom()} | {:unit, map(), atom()}

  @doc """
  Everything `name` may refer to in the domain model `domain`: its entity of that
  name, and each unit of that name among `contracts`, the models of contracts, those
  of another domain left out.
  """
  @spec candidates(atom(), map(), [map()]) :: [referent()]
  def candidates(name, domain, contracts) do
    for(e <- Map.get(domain, :entities, []), e.name == name, do: {:entity, name}) ++
      for c <- contracts,
          c.domain == domain.module,
          u <- c.units,
          u.name == name,
          do: {:unit, c, name}
  end

  @doc "What `name` refers to when exactly one thing in the domain has it, else `nil`."
  @spec resolve(atom(), map(), [map()]) :: referent() | nil
  def resolve(name, domain, contracts) do
    case candidates(name, domain, contracts) do
      [one] -> one
      _none_or_many -> nil
    end
  end

  @doc "Every name a reference may use: the domain's entities and its contracts' units."
  @spec names(map(), [map()]) :: [atom()]
  def names(domain, contracts) do
    Enum.uniq(
      Enum.map(Map.get(domain, :entities, []), & &1.name) ++
        for(c <- contracts, c.domain == domain.module, u <- c.units, do: u.name)
    )
  end

  @doc "A referent in words: `entity :service`, `unit :visit of Rehmed.Contracts.Scheduling`."
  @spec describe(referent()) :: String.t()
  def describe({:entity, name}), do: "entity #{inspect(name)}"
  def describe({:unit, c, name}), do: "unit #{inspect(name)} of #{inspect(c.module)}"
end
