defmodule EhOsContract.Contract.Links.ContextMap do
  # X11, X12 and X13: the context map holds the contracts to it (plan DD, M1 (#316)). A
  # relation between two contexts says which one depends on the other and on what terms,
  # so a reference may not cross it the other way, nor take more than its pattern lets
  # through.
  #
  # - **X11.** A reference runs against a directed relation — from its upstream context
  #   into its downstream one — or crosses `separate_ways`, which says the two do not
  #   depend on each other. Between contexts only: which way a call to an external
  #   system runs says nothing about who depends on whom.
  # - **X12.** Behind an `anticorruption_layer`, the downstream context translates what
  #   the upstream one says before using it: a policy takes the upstream contract's
  #   event and issues its own command. A read model, an effect or a process manager
  #   taking it reads the other context's model untranslated.
  # - **X13.** Behind an `open_host_service` or a `published_language`, the upstream
  #   context offers a protocol, not its model: the downstream contract consumes only
  #   the events the upstream contract `publish`es, taken from the log as any sibling's
  #   are. The publication's `fields:` are not enforced here; between applications
  #   `subscribe` takes them (the user's decision of 16 October 2026, #316).
  #
  # A reference is anything that makes one context depend on another (`crossings/2`):
  # consuming a sibling's events, a field naming an entity or a unit another context
  # owns (plan DD, L3 (#286)), and a field typed with a domain value another context
  # declares. `mix eh_os_contract.check` reads the same list for the rules it keeps: a
  # reference with no relation (`cross-bounded-context-reference-without-mapping`) and a
  # relation nothing crosses (`orphan-context-mapping`). Including an event in a process
  # module is no reference: a process belongs to no context.
  @moduledoc false

  alias EhOsContract.{Model, References}
  alias EhOsContract.Contract.Links
  alias EhOsContract.Domain.Build

  @typedoc """
  One reference from a contract into another context: the two contexts as an unordered
  pair, the contract that makes it, what it does in words, and where: at the `consumes`
  it is made by, or at the contract's `use` for a field.
  """
  @type crossing :: %{
          pair: MapSet.t(atom()),
          contract: Links.contract(),
          what: String.t(),
          at: :erl_anno.anno() | nil
        }

  @doc false
  @spec check(map()) :: [Links.violation()]
  def check(system) do
    system.contracts
    |> Enum.filter(& &1.domain)
    |> Enum.group_by(& &1.domain.module)
    |> Enum.sort_by(&inspect(elem(&1, 0)))
    |> Enum.flat_map(fn {_module, [first | _] = contracts} ->
      domain = first.domain
      against(domain, contracts) ++ patterns(domain, contracts, system)
    end)
  end

  @doc """
  Every reference from one of `contracts`, the contracts of the domain model `domain`,
  into another context of it.
  """
  @spec crossings(map(), [Links.contract()]) :: [crossing()]
  def crossings(domain, contracts) do
    context_of = Map.new(contracts, &{&1.module, &1.model.context})
    referents = References.index(domain, Enum.map(contracts, & &1.model))

    valued =
      for v <- domain.values, Map.get(v, :context) != nil, into: %{}, do: {v.name, v.context}

    for contract <- contracts,
        {other, what, at} <-
          consumed(contract, context_of) ++
            named(contract, referents, domain) ++ valued(contract, valued),
        other != nil and other != contract.model.context do
      %{pair: MapSet.new([other, contract.model.context]), contract: contract, what: what, at: at}
    end
  end

  defp consumed(contract, context_of) do
    for %{from: from} = consumes <- contract.declarations.consumes, is_atom(from) do
      other = Map.get(context_of, from) || context_of(from)
      {other, "consumes #{inspect(from)}", Links.at(consumes)}
    end
  end

  defp named(contract, referents, domain) do
    for name <- References.in_model(contract.model),
        referent = Map.get(referents, name),
        referent != nil do
      {owner(referent, domain), "names #{References.describe(referent)}", contract.at}
    end
  end

  defp valued(contract, valued) do
    for name <- References.values_in_model(contract.model),
        context = Map.get(valued, name),
        context != nil do
      {context, "uses value #{inspect(name)} of context #{inspect(context)}", contract.at}
    end
  end

  # The context that owns what a field refers to: an entity's, or its unit's contract's.
  defp owner({:entity, name}, domain),
    do: Enum.find_value(domain.entities, &(&1.name == name && &1.context))

  defp owner({:unit, contract, _name}, _domain), do: contract.context

  # A consumed contract outside the modules checked is looked up by name.
  defp context_of(module) do
    case Links.contract(module) do
      %{model: %{context: context}} -> context
      nil -> nil
    end
  end

  # --- X11 --------------------------------------------------------------------------

  # At the reference, which is what to check: the relation may be right and the
  # `consumes` wrong, and three such references are three places.
  defp against(domain, contracts) do
    references = crossings(domain, contracts)
    directed = EhOsContract.Domain.Dsl.directed_relations()

    for relation <- domain.relations,
        pair = MapSet.new(Build.endpoints(relation)),
        reference <- references,
        reference.pair == pair,
        against?(relation, reference.contract.model.context, directed),
        uniq: true do
      c = reference.contract

      {"X11: #{inspect(c.module)} in context #{inspect(c.model.context)} #{reference.what}, " <>
         "and #{describe(relation)} in #{inspect(domain.module)} says #{says(relation)}; " <>
         "change the relation or the reference", reference.at}
    end
  end

  defp against?(%{type: :separate_ways}, _from, _directed), do: true

  defp against?(%{type: type, upstream: upstream}, from, directed),
    do: type in directed and from == upstream

  defp says(%{type: :separate_ways}), do: "the two contexts do not depend on each other"

  defp says(relation),
    do: "#{inspect(relation.upstream)} does not depend on #{inspect(relation.downstream)}"

  defp describe(%{type: :separate_ways, between: [a, b]}),
    do: "relation :separate_ways between #{inspect(a)} and #{inspect(b)}"

  defp describe(relation),
    do:
      "relation #{inspect(relation.type)} from upstream #{inspect(relation.upstream)} to " <>
        "downstream #{inspect(relation.downstream)}"

  # --- X12, X13 -----------------------------------------------------------------------

  # What each pattern lets through, for a contract consuming a sibling of its upstream
  # context. A consumer upstream of its sibling is X11's.
  defp patterns(domain, contracts, system) do
    for c <- contracts,
        %{from: from} = consumes <- c.declarations.consumes,
        is_atom(from),
        sibling = Links.contract(system, from),
        sibling != nil,
        sibling.model.domain == c.model.domain,
        relation <- domain.relations,
        Map.get(relation, :upstream) == sibling.model.context,
        Map.get(relation, :downstream) == c.model.context,
        violation <- pattern(relation, c, consumes, sibling, domain) do
      violation
    end
  end

  defp pattern(%{type: :anticorruption_layer} = relation, c, _consumes, sibling, domain) do
    takers =
      for(r <- c.declarations.read_models, e <- r.projects, do: {"read model", r, e, r}) ++
        for(e <- c.declarations.effects, h <- e.handles, do: {"effect", e, h, e}) ++
        for pm <- c.declarations.process_managers,
            d <- pm.starts_on ++ pm.on ++ pm.ends_on,
            do: {"process manager", pm, d.event, d}

    for {kind, taker, event, at} <- takers,
        {:contract, from, _original} <- [Model.consumed(c.model, event)],
        from == sibling.module,
        uniq: true do
      {"X12: #{kind} #{inspect(taker.name)} takes #{inspect(event)} of " <>
         "#{inspect(sibling.module)}, and #{describe(relation)} in #{inspect(domain.module)} " <>
         "says #{inspect(c.model.context)} translates what #{inspect(sibling.model.context)} " <>
         "says before using it: only a policy takes the event, and issues a command of this " <>
         "context", Links.at(at)}
    end
  end

  defp pattern(%{type: type} = relation, _c, consumes, sibling, domain)
       when type in [:open_host_service, :published_language] do
    published = MapSet.new(sibling.model.publishes, & &1.from)

    for event <- consumes.events, not MapSet.member?(published, event) do
      offered =
        case Enum.sort(MapSet.to_list(published)) do
          [] -> "it publishes none"
          events -> "it publishes #{inspect(events)}"
        end

      {"X13: consumes #{inspect(event)} of #{inspect(sibling.module)}, which it does not " <>
         "publish, and #{describe(relation)} in #{inspect(domain.module)} says " <>
         "#{inspect(sibling.model.context)} offers only what it publishes; #{offered}",
       Links.at(consumes)}
    end
  end

  defp pattern(_relation, _c, _consumes, _sibling, _domain), do: []
end
