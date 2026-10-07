defmodule EhOsContract.Contract.Links.Processes do
  @moduledoc """
  The rules between modules for a process module, `use EhOsContract.Process` (plan DD,
  P2c, #210): what it names in its domain and in the contracts it includes, which it
  names without a compile dependency, so no rule inside the module (L2) can look them
  up. The codes are the contract's for the same thing.

  - **X1.** `domain:` names a compiled `EhOsContract.Domain`. When it does not, nothing
    else here is checked, since there is nothing to check it against.
  - **D11**, the part that needs the domain: `id:` is under the application's
    namespace, the domain's `name:`.
  - **X2.** `accountable` names an actor of the domain. A process module belongs to no
    context, since it crosses them, so the actor may be of any context of the domain,
    or of none.
  - **X5.** Every `include:` names a compiled v2 contract of the same domain, and an
    event that contract declares itself. An event a contract receives from another
    application arrives in an inbox and never enters this log (D12), and one it
    consumes from a sibling is that sibling's to include.
  - **X6.** Every `correlate` field is in every included event, required and
    non-personal, as a contract's `correlate` is checked for the sibling events it
    includes (`EhOsContract.Contract.Links.Siblings.problems/4`). A process module
    has no events of its own to type the field, so it is held to what a run's key may
    be, an `:id` (F8), and every included event carries it as the same identifier: a
    plain `:id` agrees with one domain value resting on `:id`, two different values do
    not, whatever the order of the includes.

  X7, a process module's `id:` taken by another process, is `Links.System`'s. The
  error stands at the module's `use` for what names the whole module, and at the stage
  for what one of its includes gets wrong.
  """

  alias EhOsContract.DslRules
  alias EhOsContract.Contract.{Links, Rules}

  @doc false
  @spec check(map()) :: [Links.violation()]
  def check(system), do: Enum.flat_map(system.processes, &process(&1, system))

  defp process(%{domain: nil} = p, _system) do
    [
      {"X1: #{inspect(p.module)} names domain #{inspect(p.model.domain)}, which is not a " <>
         "compiled EhOsContract.Domain", p.at}
    ]
  end

  defp process(p, system) do
    included = included(p, system)
    namespace(p) ++ accountable(p) ++ x5(p, included) ++ x6(p, included)
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

    if name in names,
      do: [],
      else: [
        {"X2: #{where(p)}: accountable #{inspect(name)} is not an actor of " <>
           "#{inspect(domain.module)}; #{suggest(name, names)}", p.at}
      ]
  end

  # --- X5 ---------------------------------------------------------------------------

  # Every include of every stage, with the contract it names as the rules read it,
  # `nil` when it is not one.
  defp included(p, system) do
    for stage <- p.declarations.stages,
        {module, event} <- EhOsContract.Process.Rules.includes(stage),
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

  # --- X6 ---------------------------------------------------------------------------

  defp x6(p, included) do
    values = EhOsContract.Codec.values(p.model.domain)

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
