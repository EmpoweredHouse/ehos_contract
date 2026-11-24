defmodule EhosContract.References do
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
  Every name a field of `model`, a contract's model, refers to, each once, in the order
  its declarations come: its units' states, commands, events, read models, process
  managers' states, consumed events, queries' parameters and domain services'
  functions. Only declared fields count, never a key of a scenario's data.
  """
  @spec in_model(map()) :: [atom()]
  def in_model(model) do
    model
    |> declared_fields()
    |> Enum.flat_map(&List.wrap(Map.get(&1, :refers_to)))
    |> Enum.uniq()
  end

  # Plan DD, M1 (#316): a value another context declares makes a reference too.
  @doc """
  Every type name a field of `model`, a contract's model, is given, each once, in the
  order its declarations come, a list's element type included: the domain values it
  uses among the built-in types, which a reader tells apart by the domain's values.
  """
  @spec values_in_model(map()) :: [atom()]
  def values_in_model(model) do
    model
    |> declared_fields()
    |> Enum.flat_map(&type_names(Map.get(&1, :type)))
    |> Enum.uniq()
  end

  @doc "The type names in `type`: itself when it is a name, a list's element type's, none for an enum or an `{:id, name}`."
  @spec type_names(term()) :: [atom()]
  def type_names({:list, inner}), do: type_names(inner)
  def type_names(name) when is_atom(name) and name != nil, do: [name]
  def type_names(_other), do: []

  defp declared_fields(model) do
    within = fn key, fields -> Enum.flat_map(Map.get(model, key, []), fields) end

    Enum.concat([
      within.(:units, & &1.state.fields),
      within.(:commands, & &1.fields),
      within.(:events, & &1.fields),
      within.(:read_models, & &1.fields),
      within.(:process_managers, & &1.state.fields),
      within.(:consumes, &Map.get(&1, :fields, [])),
      within.(:queries, &Map.get(&1, :params, [])),
      within.(:domain_services, fn service ->
        Enum.flat_map(service.functions, &[&1.returns | &1.arguments])
      end)
    ])
    |> Enum.filter(&is_map/1)
  end

  @doc "Every name a reference may use: the domain's entities and its contracts' units."
  @spec names(map(), [map()]) :: [atom()]
  def names(domain, contracts) do
    Enum.uniq(
      Enum.map(Map.get(domain, :entities, []), & &1.name) ++
        for(c <- contracts, c.domain == domain.module, u <- c.units, do: u.name)
    )
  end

  @doc "A referent in words: `entity :service`, `unit :loan of Lending.Contracts.Circulation`."
  @spec describe(referent()) :: String.t()
  def describe({:entity, name}), do: "entity #{inspect(name)}"
  def describe({:unit, c, name}), do: "unit #{inspect(name)} of #{inspect(c.module)}"
end
