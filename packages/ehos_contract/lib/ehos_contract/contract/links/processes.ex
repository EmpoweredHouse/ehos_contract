defmodule EhosContract.Contract.Links.Processes do
  # The rules between modules for a process module, `use EhosContract.Process` (plan DD,
  # P2c, #210): what it names in its domain and in the contracts it includes, which it
  # names without a compile dependency, so no rule inside the module (L2) can look them
  # up. The codes are the contract's for the same thing.
  #
  # - **X1.** `domain:` names a compiled `EhosContract.Domain`. When it does not, nothing
  #   else here is checked, since there is nothing to check it against.
  # - **D11**, the part that needs the domain: `id:` is under the application's
  #   namespace, the domain's `name:`.
  # - **X2.** `accountable` names an actor of the domain. A process module belongs to no
  #   context, since it crosses them, so the actor may be of any context of the domain,
  #   or of none.
  # - **X5.** Every `include:` names a compiled v2 contract of the same domain, and an
  #   event that contract declares itself. An event a contract receives from another
  #   application arrives in an inbox and never enters this log (D12), and one it
  #   consumes from a sibling is that sibling's to include.
  # - **X6.** Every `correlate` field is in every included event, required and
  #   non-personal, as a contract's `correlate` is checked for the sibling events it
  #   includes (`EhosContract.Contract.Links.Siblings.problems/4`). A process module
  #   has no events of its own to type the field, so it is held to what a run's key may
  #   be, an `:id` (F8), and every included event carries it as the same identifier: a
  #   plain `:id` agrees with one domain value resting on `:id`, two different values do
  #   not, whatever the order of the includes.
  # - **X9 and X4 in a scenario** (plan DD, S2, #251). A given's data fits the event the
  #   contract that declares it declares, as a sibling event's data in a contract's
  #   scenario does (`EhosContract.Contract.Links.Scenarios`): its fields, every required
  #   one and its unit's identity, each value of its type. An outage is of an external
  #   the promise's `eventually` or `or_else` depends on, or one it `waits_on`: `from`
  #   already happened, so what it needs was working, and an outage of anything else
  #   excuses nothing in the report (`EhosContract.Trace`), so a scenario of one would
  #   show what never happens.
  # - **X4 for a promise** (plan DD, OW1 (#355)). Each system a promise `waits_on` is an
  #   external of the domain, and not one its `eventually` or `or_else` already depends
  #   on, which excuses it without saying so: two declarations of one dependency would
  #   drift, and a reader could not tell which one is meant. And a contract the process
  #   includes uses it, an event depending on it or an effect calling it: an outage is
  #   recorded only under such a contract, and the report reads only the included ones,
  #   so without one the promise would wait on a system no outage of which it can see.
  #
  # X7, a process module's `id:` taken by another process, is `Links.System`'s. The
  # error stands at the module's `use` for what names the whole module, and at the stage
  # for what one of its includes gets wrong.
  @moduledoc false

  alias EhosContract.DslRules
  alias EhosContract.Contract.{Links, Rules}

  @doc false
  @spec check(map()) :: [Links.violation()]
  def check(system), do: Enum.flat_map(system.processes, &process(&1, system))

  defp process(%{domain: nil} = p, _system) do
    [
      {"X1: #{inspect(p.module)} names domain #{inspect(p.model.domain)}, which is not a " <>
         "compiled EhosContract.Domain", p.at}
    ]
  end

  defp process(p, system) do
    included = included(p, system)

    namespace(p) ++
      accountable(p) ++
      x5(p, included) ++
      x6(p, included) ++
      waits_on(p, included) ++ given_data(p, included) ++ outages(p, included)
  end

  defp where(p), do: "process #{inspect(p.model.id)}"

  # --- D11 --------------------------------------------------------------------------

  defp namespace(%{model: %{id: id}, domain: domain} = p) do
    prefix = "#{domain.name}."

    if String.starts_with?(id, prefix),
      do: [],
      else: [
        {"D11: the process's id: #{inspect(id)} is outside the application's namespace " <>
           "#{inspect(prefix)}, the name: of #{inspect(domain.module)}", p.at}
      ]
  end

  # --- X2 ---------------------------------------------------------------------------

  defp accountable(%{model: %{accountable: nil}}), do: []

  defp accountable(%{model: %{accountable: name}, domain: domain} = p) do
    names = Enum.map(domain.actors, & &1.name)
    # A typo is never pointed at the seed, which X2 refuses as accountable below.
    suggestable = for %{kind: kind, name: n} <- domain.actors, kind != :seed, do: n

    cond do
      name not in names ->
        [
          {"X2: #{where(p)}: accountable #{inspect(name)} is not an actor of " <>
             "#{inspect(domain.module)}; #{suggest(name, suggestable)}", p.at}
        ]

      # #683: the seed loads sample data; it answers for no process of the business.
      Enum.any?(domain.actors, &(&1.name == name and &1.kind == :seed)) ->
        [
          {"X2: #{where(p)}: accountable #{inspect(name)} is the domain's seed, which " <>
             "answers for no process; name the role that does", p.at}
        ]

      true ->
        []
    end
  end

  # --- X5 ---------------------------------------------------------------------------

  # Every include of every stage, with the contract it names as the rules read it,
  # `nil` when it is not one.
  defp included(p, system) do
    for stage <- p.declarations.stages,
        {module, event} <- EhosContract.Process.Rules.includes(stage),
        do: %{
          stage: stage,
          module: module,
          event: event,
          contract: Links.contract(system, module)
        }
  end

  defp x5(p, included) do
    for %{contract: contract} = include <- included,
        problem <- include_problems(p, include, contract) do
      {"X5: #{where(p)}, stage #{inspect(include.stage.name)}, includes " <>
         "#{inspect(include.event)} from #{inspect(include.module)}, " <> problem,
       Links.at(include.stage)}
    end
  end

  defp include_problems(_p, _include, nil), do: ["which is not a compiled contract"]

  defp include_problems(p, include, contract) do
    names = Enum.map(contract.model.events, & &1.name)
    consumed = Map.new(Rules.consumed(contract.declarations))

    cond do
      contract.model.domain != p.model.domain ->
        [
          "a contract of domain #{inspect(contract.model.domain)}, not " <>
            "#{inspect(p.model.domain)}: another application's events arrive only through " <>
            "a publish (D11)"
        ]

      include.event in names ->
        []

      MapSet.member?(Rules.received(contract.declarations), include.event) ->
        [
          "which it receives from another application into an inbox, not into this log " <>
            "(D12); a run across applications is assembled by EHOS"
        ]

      Map.has_key?(consumed, include.event) ->
        [
          "which it consumes from #{inspect(consumed[include.event].from)}; include it " <>
            "from the contract that declares it"
        ]

      true ->
        hint =
          case DslRules.closest(include.event, names) do
            nil -> "it declares #{inspect(names)}"
            suggestion -> "did you mean #{inspect(suggestion)}?"
          end

        ["which declares no such event (#{Links.place(contract.at)}); #{hint}"]
    end
  end

  # --- X4: what a promise waits on -------------------------------------------------

  defp waits_on(%{domain: domain} = p, included) do
    externals = Enum.map(domain.externals, & &1.name)

    used =
      for %{contract: %{model: model}} <- included,
          external <-
            Enum.map(model.events, & &1.depends_on) ++
              Enum.flat_map(model.effects, &Enum.map(List.wrap(&1.calls), fn c -> system(c) end)),
          external != nil,
          into: MapSet.new(),
          do: external

    for promise <- p.declarations.promises,
        name <- Enum.uniq(promise.waits_on),
        problem <-
          waits_on_problems(name, depends_on(promise, included), used, externals, domain) do
      {"X4: promise #{inspect(promise.name)}: waits_on #{inspect(name)} #{problem}",
       Links.at(promise)}
    end
  end

  defp waits_on_problems(name, depends, used, externals, domain) do
    cond do
      name not in externals ->
        ["is not an external of #{inspect(domain.module)}; #{suggest(name, externals)}"]

      name in depends ->
        [
          "is what its eventually or or_else already depends_on, which excuses it without " <>
            "saying so; leave it out of waits_on"
        ]

      not MapSet.member?(used, name) ->
        [
          "is used by no contract the process includes: no event of one depends_on it and " <>
            "no effect calls it, so no outage of it is recorded where the report reads; " <>
            "include the contract whose step calls it"
        ]

      true ->
        []
    end
  end

  defp system({external, _operation}), do: external
  defp system(external), do: external

  # --- X9, X4: scenarios -----------------------------------------------------------

  defp given_data(p, included) do
    values = Map.new(p.domain.values, &{&1.name, &1})

    for scenario <- p.declarations.scenarios,
        given <- scenario.given,
        {contract, event} <- [declared(included, given.event)],
        problem <- given_problems(contract, event, given.data, values) do
      {"X9: scenario #{inspect(scenario.description)}: event #{inspect(given.event)} of " <>
         "#{inspect(contract.module)}: #{problem}", Links.at(given)}
    end
  end

  # Unlike a contract's scenario, which is about one stream and fills its identity in,
  # a process's scenario is about runs and items told apart by the units' identities,
  # so each given names its unit, as every event in the log does.
  defp given_problems(contract, event, data, values) do
    identity = Enum.find(contract.model.units, &(&1.name == event.unit)).identity
    fields = event.fields ++ for(name <- identity, do: %{name: name, type: :id, optional: false})
    Links.Scenarios.sibling_problems(Enum.uniq_by(fields, & &1.name), [], data, values, true)
  end

  defp outages(p, included) do
    for scenario <- p.declarations.scenarios,
        [judged] <- [scenario.trigger],
        promise = Enum.find(p.model.promises, &(&1.name == judged.name)),
        promise != nil,
        depends = depends_on(promise, included),
        waits = Map.get(promise, :waits_on, []),
        outage <- scenario.outages,
        outage.external not in (depends ++ waits) do
      on =
        case depends do
          [] -> "on no external"
          some -> "on #{inspect(some)}"
        end

      waits_on =
        case waits do
          [] -> "it waits on no other"
          some -> "it waits_on #{inspect(some)}"
        end

      {"X4: scenario #{inspect(scenario.description)}: outage #{inspect(outage.external)} " <>
         "is of no external promise #{inspect(promise.name)} waits on; its eventually and " <>
         "or_else depend #{on}, #{waits_on}, and an outage of anything else excuses nothing",
       Links.at(outage)}
    end
  end

  # The externals the events a promise waits on depend on, as the contracts that declare
  # them say.
  defp depends_on(promise, included) do
    for name <- [promise.eventually, promise.or_else],
        name != nil,
        {_contract, event} <- [declared(included, name)],
        event.depends_on != nil,
        uniq: true,
        do: event.depends_on
  end

  # The included event of this name, with the contract that declares it; `nil` when X5
  # has refused the include.
  defp declared(included, name) do
    Enum.find_value(included, fn
      %{event: ^name, contract: %{} = contract} ->
        case Enum.find(contract.model.events, &(&1.name == name)) do
          nil -> nil
          event -> {contract, event}
        end

      _include ->
        nil
    end)
  end

  # --- X6 ---------------------------------------------------------------------------

  defp x6(p, included) do
    values = EhosContract.Codec.values(p.model.domain)

    events =
      for %{contract: %{} = contract} = include <- included,
          contract.model.domain == p.model.domain,
          event = Enum.find(contract.model.events, &(&1.name == include.event)),
          event != nil do
        declared =
          Enum.find(Rules.local_events(contract.declarations), &(&1.name == include.event))

        {include, %{sibling: contract.module, event: event, at: Links.at(declared)}}
      end

    for field <- p.model.correlate,
        type = key_type(events, field, values),
        {include, consumed} <- events,
        problem <- Links.Siblings.problems(consumed, field, type, values) do
      {"X6: #{where(p)} includes #{inspect(include.event)} and correlates on " <>
         "#{inspect(field)}, #{problem}", Links.at(include.stage)}
    end
  end

  # The type every included event carries `field` as: among those that carry it as an
  # identifier, the first that is not a plain `:id`, so that a domain value sets it
  # whatever the order of the includes, and a plain `:id` agrees with it while a
  # second, different value does not (`Links.Siblings.problems/4`); `:id` when none
  # carries it as more than that (F8).
  defp key_type(events, field, values) do
    identifiers =
      for {_include, consumed} <- events,
          %{type: type} <- [Enum.find(consumed.event.fields, &(&1.name == field))],
          Links.Siblings.problems(consumed, field, :id, values) == [],
          do: type

    Enum.find(identifiers, :id, &(&1 != :id))
  end

  defp suggest(name, names) do
    case DslRules.closest(name, names) do
      nil -> "it declares #{inspect(Enum.sort(names))}"
      suggestion -> "did you mean #{inspect(suggestion)}?"
    end
  end
end
