defmodule EhOsContract.Contract.Rules do
  # The rules a v2 contract must satisfy to compile: v2 §6, layer L2.
  #
  # A transformer, not a verifier, and every violation is reported at once, in one
  # error that names each declaration's file and line (`EhOsContract.DslRules`). The
  # rules come in groups, one module each, named after v2 §6's letters. Each group
  # reads the contract through `declarations/1`, so none of them walks Spark's
  # structure on its own.
  #
  # What L2 cannot see is left to L3, the Mix compiler `compile.eh_os_contract`
  # (`EhOsContract.Contract.Links`): whether an actor, a value type, a subject or
  # an external exists in the domain, and whether a consumed contract has the events
  # and fields this one reads. The domain and the consumed contracts are named without
  # a compile dependency (v2 §8), so a transformer has nothing to look them up in.
  @moduledoc false

  use Spark.Dsl.Transformer

  alias EhOsContract.DslRules
  alias EhOsContract.Contract.Dsl
  alias EhOsContract.Contract.Rules
  alias Spark.Dsl.Transformer

  @groups [
    Rules.Names,
    Rules.Fields,
    Rules.Units,
    Rules.Lifecycles,
    Rules.Process,
    Rules.Consumes,
    Rules.Consumers,
    Rules.Boundaries,
    Rules.Scenarios
  ]

  @impl true
  def before?(EhOsContract.Contract.Build), do: true
  def before?(_), do: false

  @impl true
  def transform(dsl) do
    declarations = declarations(dsl)

    violations =
      Enum.flat_map(@groups, & &1.check(declarations)) ++
        Rules.Boundaries.contract_id(contract_id(dsl) || %{value: nil, at: use_at(dsl)})

    DslRules.result(dsl, [:contract], violations)
  end

  @doc false
  @spec declarations(map()) :: map()
  def declarations(dsl) do
    entities = Transformer.get_entities(dsl, [:contract])
    of = fn struct -> for %{__struct__: ^struct} = e <- entities, do: e end

    %{
      module: Transformer.get_persisted(dsl, :module),
      units: of.(Dsl.Unit),
      policies: of.(Dsl.Policy),
      effects: of.(Dsl.Effect),
      process_managers: of.(Dsl.ProcessManager),
      read_models: of.(Dsl.ReadModel),
      queries: of.(Dsl.Query),
      domain_services: of.(Dsl.DomainService),
      consumes: of.(Dsl.Consumes),
      publishes: of.(Dsl.Publish),
      processes: of.(Dsl.ProcessDeclaration),
      scenarios: of.(Dsl.Scenario)
    }
  end

  @doc false
  # Plan DD, ID1: the contract's `id:`, as written, with where its `use` stands (`nil`
  # when the file is not known), or `nil` when it names none. Kept beside the
  # declarations, not among them: every rule that walks all of them reads lists of
  # Spark entities.
  @spec contract_id(map()) :: %{value: String.t(), at: :erl_anno.anno() | nil} | nil
  def contract_id(dsl) do
    case Transformer.get_persisted(dsl, :eh_os_contract_contract) do
      %{id: id} when id != nil -> %{value: id, at: use_at(dsl)}
      _ -> nil
    end
  end

  defp use_at(dsl) do
    case {Transformer.get_persisted(dsl, :file),
          Transformer.get_persisted(dsl, :eh_os_contract_line)} do
      {file, line} when is_binary(file) and is_integer(line) ->
        :erl_anno.set_file(String.to_charlist(file), :erl_anno.new(line))

      _ ->
        nil
    end
  end

  @doc "A unit's events, whether written in a stage group or outside one."
  @spec events(struct()) :: [struct()]
  def events(%Dsl.Unit{} = unit), do: unit.events ++ Enum.flat_map(unit.stages, & &1.events)

  @doc "Every event of every unit."
  @spec local_events(map()) :: [struct()]
  def local_events(declarations), do: Enum.flat_map(declarations.units, &events/1)

  @doc "Every command of every unit."
  @spec commands(map()) :: [struct()]
  def commands(declarations), do: Enum.flat_map(declarations.units, & &1.commands)

  @doc """
  The events this contract consumes, under the names they have here, each with the
  `consumes` declaration that brings it in.
  """
  @spec consumed(map()) :: [{atom(), struct()}]
  def consumed(declarations) do
    Enum.flat_map(declarations.consumes, fn
      %Dsl.Consumes{from: from, as: as} = consumes when is_binary(from) ->
        if is_atom(as) and as != nil, do: [{as, consumes}], else: []

      %Dsl.Consumes{} = consumes ->
        renames =
          if Keyword.keyword?(List.wrap(consumes.as)), do: List.wrap(consumes.as), else: []

        for event <- consumes.events, do: {Keyword.get(renames, event, event), consumes}
    end)
  end

  @doc """
  The local names of events received from another application, `subscribe "<name>"`.
  They go to an inbox, not into this log (D12), so nothing that reads the log — a
  run, a boundary's append condition — can take them in.
  """
  @spec received(map()) :: MapSet.t(atom())
  def received(declarations) do
    for {as, %Dsl.Consumes{from: from}} <- consumed(declarations),
        is_binary(from),
        into: MapSet.new(),
        do: as
  end

  @doc """
  What a refusal calls an event `consumed/1` returns: a sibling's is consumed, another
  application's subscribed to (plan N2).
  """
  @spec arrived(struct()) :: String.t()
  def arrived(%Dsl.Consumes{from: from}) when is_binary(from), do: "subscribed event"
  def arrived(%Dsl.Consumes{}), do: "consumed event"

  @doc "The fields of every state a unit or a process manager declares."
  @spec state_fields([struct()]) :: [struct()]
  def state_fields(states), do: Enum.flat_map(states, & &1.fields)
end
