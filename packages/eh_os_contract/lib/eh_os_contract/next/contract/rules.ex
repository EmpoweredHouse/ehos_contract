defmodule EhOsContract.Next.Contract.Rules do
  @moduledoc """
  The rules a v2 contract must satisfy to compile: v2 §6, layer L2.

  A transformer, not a verifier, and every violation is reported at once, in one
  error that names each declaration's file and line (`EhOsContract.DslRules`). The
  rules come in groups, one module each, named after v2 §6's letters. Each group
  reads the contract through `declarations/1`, so none of them walks Spark's
  structure on its own.

  What L2 cannot see is left to L3, the Mix compiler `compile.eh_os_contract`
  (`EhOsContract.Next.Contract.Links`): whether an actor, a value type, a subject or
  an external exists in the domain, and whether a consumed contract has the events
  and fields this one reads. The domain and the consumed contracts are named without
  a compile dependency (v2 §8), so a transformer has nothing to look them up in.
  """

  use Spark.Dsl.Transformer

  alias EhOsContract.DslRules
  alias EhOsContract.Next.Contract.Dsl
  alias EhOsContract.Next.Contract.Rules
  alias Spark.Dsl.Transformer

  @groups [
    Rules.Names,
    Rules.Fields,
    Rules.Units,
    Rules.Process,
    Rules.Consumes,
    Rules.Consumers,
    Rules.Boundaries,
    Rules.Scenarios
  ]

  @impl true
  def before?(EhOsContract.Next.Contract.Build), do: true
  def before?(_), do: false

  @impl true
  def transform(dsl) do
    declarations = declarations(dsl)
    DslRules.result(dsl, [:contract], Enum.flat_map(@groups, & &1.check(declarations)))
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
      consumes: of.(Dsl.Consumes),
      publishes: of.(Dsl.Publish),
      processes: of.(Dsl.ProcessDeclaration),
      scenarios: of.(Dsl.Scenario)
    }
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
  The local names of events received from another application, `consumes "<name>"`.
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

  @doc "The fields of every state a unit or a process manager declares."
  @spec state_fields([struct()]) :: [struct()]
  def state_fields(states), do: Enum.flat_map(states, & &1.fields)
end
