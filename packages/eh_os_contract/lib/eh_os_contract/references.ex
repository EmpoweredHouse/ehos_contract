defmodule EhOsContract.References do
  # What a field typed `{:id, name}` identifies (plan DD, L3 (#286)): an entity of the
  # domain, which the application keeps, or a unit of one of the domain's contracts,
  # which its events make. The model stores either as `type: :id, refers_to: name`
  # (plan EM2), so the codec, tags and typespecs see a plain `:id`, and the name is
  # resolved here, against the domain and its contracts.
  #
  # In a contract a name has to match exactly one: the compiler between modules refuses
  # a reference that matches none or several (X3). The domain knows only entities, so
  # a field of a value or an entity names one even when a unit has the same name, and
  # `resolve/3` and `index/2` therefore answer the entity first, then the one unit of
  # that name. `check` and the pages read them; the graph resolves the same way within
  # what one document holds.
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

  @doc """
  What `name` refers to: the domain's entity of that name, else the one unit of it,
  else `nil`.
  """
  @spec resolve(atom(), map(), [map()]) :: referent() | nil
  def resolve(name, domain, contracts), do: pick(candidates(name, domain, contracts))

  defp pick([{:entity, _name} = entity | _units]), do: entity
  defp pick([{:unit, _c, _name} = unit]), do: unit
  defp pick(_none_or_many), do: nil

  @doc """
  What each name refers to, for a reader that resolves many: `resolve/3`'s answer for
  every name it answers, in one pass over the domain and `contracts`.
  """
  @spec index(map(), [map()]) :: %{atom() => referent()}
  def index(domain, contracts) do
    entities = for e <- Map.get(domain, :entities, []), do: {e.name, {:entity, e.name}}

    units =
      for c <- contracts,
          c.domain == domain.module,
          u <- c.units,
          do: {u.name, {:unit, c, u.name}}

    for {name, candidates} <- Enum.group_by(entities ++ units, &elem(&1, 0), &elem(&1, 1)),
        referent = pick(candidates),
        referent != nil,
        into: %{},
        do: {name, referent}
  end

  @doc """
  Every name a field of `model`, a contract's model, refers to, at any depth and in the
  order met, each once.
  """
  @spec in_model(map()) :: [atom()]
  def in_model(model), do: model |> names_in() |> Enum.uniq()

  defp names_in(%{refers_to: name} = map),
    do: [name | map |> Map.delete(:refers_to) |> names_in()]

  defp names_in(%{} = map), do: map |> Map.values() |> Enum.flat_map(&names_in/1)
  defp names_in(list) when is_list(list), do: Enum.flat_map(list, &names_in/1)
  defp names_in(_other), do: []

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
