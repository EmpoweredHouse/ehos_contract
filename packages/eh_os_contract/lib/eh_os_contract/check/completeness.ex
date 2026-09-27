defmodule EhOsContract.Check.Completeness do
  @moduledoc """
  ESDM's completeness rules over v2 contracts and their domains (v2 §6, L5; plan
  EL1): what a model may legally leave out and a reader should still hear about.

  ESDM makes them warnings and so does this module; the structural rules ESDM has
  are errors here, in L2 and L3. Each rule reads a whole domain at once — every
  contract naming it — because what makes an actor an orphan or a context empty is
  that *no* contract uses it, which no one contract can tell.

  A domain's declarations are read with the file and line Spark kept, as L3 reads a
  contract's, so a finding points at the actor, the context or the relation it is
  about.
  """

  alias EhOsContract.Check.Finding
  alias EhOsContract.Domain
  alias EhOsContract.Next.Contract.Links

  @doc """
  Every finding of a completeness rule about `contracts`, v2 contract modules,
  and the domains they name.
  """
  @spec findings([module()]) :: [Finding.t()]
  def findings(contracts) do
    linked = contracts |> Enum.map(&Links.contract/1) |> Enum.reject(&is_nil/1)

    for {domain, members} <- Enum.group_by(linked, & &1.model.domain),
        members = Enum.reject(members, &is_nil(&1.domain)),
        members != [],
        finding <- domain(domain, members) do
      finding
    end
  end

  defp domain(module, contracts) do
    model = hd(contracts).domain
    declared = declared(module)

    Enum.concat([
      orphan_actors(model, declared, contracts),
      orphan_externals(model, declared, contracts),
      empty_contexts(model, declared, contracts),
      orphan_relations(model, declared, contracts),
      unmapped_references(model, contracts)
    ])
  end

  # The domain's declarations as Spark kept them, with where each was written.
  defp declared(module) do
    entities = Spark.Dsl.Extension.get_entities(module, [:domain])
    of = fn struct -> for %{__struct__: ^struct} = e <- entities, do: e end

    %{
      actors: of.(Domain.Dsl.Actor),
      externals: of.(Domain.Dsl.External),
      contexts: of.(Domain.Dsl.Context),
      relations: of.(Domain.Dsl.Relation)
    }
  end

  defp at(declarations, name) do
    case Enum.find(declarations, &(&1.name == name)) do
      nil -> nil
      declaration -> Links.at(declaration)
    end
  end

  # ESDM's `orphan-actor`: an actor no command, query, recorded event or process
  # names. A scenario's actor is in a command's `by:` already (S7).
  defp orphan_actors(model, declared, contracts) do
    named =
      MapSet.new(
        for %{model: m} <- contracts,
            actor <-
              Enum.flat_map(m.commands, & &1.by) ++
                Enum.flat_map(m.queries, & &1.by) ++
                Enum.flat_map(m.events, & &1.recorded_by) ++
                List.wrap(m.process && m.process.accountable),
            do: actor
      )

    for actor <- model.actors, not MapSet.member?(named, actor.name) do
      Finding.new(
        "orphan-actor",
        "actor #{inspect(actor.name)} of #{inspect(model.module)} is in no command's or query's " <>
          "`by:`, no event's `recorded_by:` and no process's `accountable`, so no contract gives " <>
          "it anything to do",
        at(declared.actors, actor.name)
      )
    end
  end

  # ESDM's `orphan-external-system`: an external no actor stands for, no effect calls
  # and no event depends on.
  defp orphan_externals(model, declared, contracts) do
    named =
      MapSet.new(
        Enum.map(model.actors, & &1.backed_by) ++
          for(
            %{model: m} <- contracts,
            external <-
              Enum.flat_map(m.effects, &List.wrap(&1.calls)) ++
                Enum.flat_map(m.events, &List.wrap(&1.depends_on)),
            do: external
          )
      )

    for external <- model.externals, not MapSet.member?(named, external.name) do
      Finding.new(
        "orphan-external-system",
        "external #{inspect(external.name)} of #{inspect(model.module)} backs no actor, and no " <>
          "effect `calls:` it and no event `depends_on:` it",
        at(declared.externals, external.name)
      )
    end
  end

  # ESDM's `bounded-context-without-content`, which counts aggregates, boundaries and
  # read models: here a context no contract belongs to, since a contract is what
  # holds them.
  defp empty_contexts(model, declared, contracts) do
    used = MapSet.new(contracts, & &1.model.context)

    for context <- model.contexts, not MapSet.member?(used, context.name) do
      Finding.new(
        "bounded-context-without-content",
        "context #{inspect(context.name)} of #{inspect(model.module)} is the `context:` of no " <>
          "contract, so nothing is decided, recorded or read in it",
        at(declared.contexts, context.name)
      )
    end
  end

  # ESDM's `orphan-context-mapping`: a relation no reference crosses, in either
  # direction.
  defp orphan_relations(model, declared, contracts) do
    crossing = MapSet.new(crossings(model, contracts), &elem(&1, 0))

    for {relation, index} <- Enum.with_index(model.relations),
        pair = relation |> Domain.Build.endpoints() |> MapSet.new(),
        not MapSet.member?(crossing, pair) do
      [a, b] = Domain.Build.endpoints(relation)

      Finding.new(
        "orphan-context-mapping",
        "relation #{inspect(relation.type)} between #{inspect(a)} and #{inspect(b)} in " <>
          "#{inspect(model.module)} is crossed by no reference: no contract of one consumes a " <>
          "contract of the other or names an entity it owns",
        declared.relations |> Enum.at(index) |> then(&(&1 && Links.at(&1)))
      )
    end
  end

  # ESDM's `cross-bounded-context-reference-without-mapping`: a contract that consumes
  # a contract of another context, or names an entity another context owns, with no
  # relation declared between the two contexts. One finding per reference.
  defp unmapped_references(model, contracts) do
    mapped = MapSet.new(model.relations, &MapSet.new(Domain.Build.endpoints(&1)))

    for {pair, contract, what, at} <- crossings(model, contracts),
        not MapSet.member?(mapped, pair),
        uniq: true do
      other = pair |> MapSet.delete(contract.model.context) |> Enum.at(0)

      Finding.new(
        "cross-bounded-context-reference-without-mapping",
        "#{inspect(contract.module)} in context #{inspect(contract.model.context)} #{what} of " <>
          "context #{inspect(other)}, and #{inspect(model.module)} declares no relation between " <>
          "the two",
        at
      )
    end
  end

  # Every reference from a contract into another context: `{contexts, contract, what,
  # at}`, the contexts as an unordered pair, `at` the `consumes` it is made by or, for
  # an entity named in a field, the contract's `use`.
  defp crossings(model, contracts) do
    context_of = Map.new(contracts, &{&1.module, &1.model.context})
    owner = Map.new(model.entities, &{&1.name, &1.context})

    for contract <- contracts,
        {other, what, at} <-
          for(
            %{from: from} = consumes <- contract.declarations.consumes,
            is_atom(from),
            other = Map.get(context_of, from) || context_of(from),
            do: {other, "consumes #{inspect(from)}", Links.at(consumes)}
          ) ++
            for(
              entity <- contract.model |> references() |> Enum.uniq(),
              other = Map.get(owner, entity),
              do: {other, "names entity #{inspect(entity)}", contract.at}
            ),
        other != nil and other != contract.model.context do
      {MapSet.new([other, contract.model.context]), contract, what, at}
    end
  end

  # A consumed contract outside the modules checked is looked up by name, as L3 does.
  defp context_of(module) do
    case Links.contract(module) do
      %{model: %{context: context}} -> context
      nil -> nil
    end
  end

  # Every entity a field of the model refers to (plan EM2), at any depth.
  defp references(%{refers_to: entity} = map),
    do: [entity | map |> Map.delete(:refers_to) |> references()]

  defp references(%{} = map), do: map |> Map.values() |> Enum.flat_map(&references/1)
  defp references(list) when is_list(list), do: Enum.flat_map(list, &references/1)
  defp references(_other), do: []
end
