defmodule EhOsContract.Next.Contract.Links.Siblings do
  @moduledoc """
  X5–X6 of v2 §6: what a contract consumes from a sibling contract of the same
  application, `consumes Sibling, events`, checked against the sibling as it is
  compiled now — which is how a change to an event reaches every subscriber (v2 §7).

  - **X5.** The sibling is a compiled v2 contract of the same domain, and it
    declares every event named. A contract of another domain is another
    application's, whose events arrive only through a `publish` (D11).
  - **X6.** The fields a subscriber's declarations use exist in the sibling's event
    with the type the subscriber gives them, and are neither `optional:` nor
    `personal:`, since each tells which run or which boundary an event belongs to
    (F4): the process's `correlate` for every event it `include`s, a process
    manager's `correlate` for every event it handles, and a boundary's `match:` for
    every event it `consults`. The error stands at the subscriber's declaration and
    names the sibling's event, with its file and line.

  `projects` names an event and no field of it: which fields a projection reads is
  in its implementation, which matches on the sibling's own struct, so the compiler
  refuses a field that is gone there (v2 §7, the third mechanism). For `projects`
  X6 is therefore X5.
  """

  alias EhOsContract.DslRules
  alias EhOsContract.Next.Contract.{Links, Rules}

  @doc false
  @spec check(map()) :: [Links.violation()]
  def check(system), do: Enum.flat_map(system.contracts, &contract/1)

  defp contract(c) do
    siblings =
      for %{from: from} = consumes <- c.declarations.consumes,
          is_atom(from),
          do: {consumes, Links.contract(from)}

    existence = Enum.flat_map(siblings, fn {consumes, sibling} -> x5(c, consumes, sibling) end)
    events = consumed_events(c, siblings)

    existence ++ correlation(c, events) ++ managers(c, events) ++ matches(c, events)
  end

  # --- X5 ---------------------------------------------------------------------------

  defp x5(_c, consumes, nil) do
    [
      {"X5: consumes #{inspect(consumes.from)}, which is not a compiled v2 contract",
       Links.at(consumes)}
    ]
  end

  defp x5(c, consumes, sibling) do
    if sibling.model.domain != c.model.domain do
      [
        {"X5: consumes #{inspect(consumes.from)}, a contract of domain " <>
           "#{inspect(sibling.model.domain)}, not #{inspect(c.model.domain)}: another " <>
           "application's events arrive only through a publish (D11)", Links.at(consumes)}
      ]
    else
      names = Enum.map(sibling.model.events, & &1.name)

      for event <- consumes.events, event not in names do
        hint =
          case DslRules.closest(event, names) do
            nil -> "it declares #{inspect(names)}"
            suggestion -> "did you mean #{inspect(suggestion)}?"
          end

        {"X5: consumes #{inspect(event)} from #{inspect(sibling.module)} " <>
           "(#{Links.place(sibling.at)}), which declares no such event; #{hint}",
         Links.at(consumes)}
      end
    end
  end

  # --- X6 ---------------------------------------------------------------------------

  # Every sibling event this contract consumes, under its local name: the sibling,
  # its fields as the sibling's model has them, and where the sibling declares it.
  defp consumed_events(c, siblings) do
    for {consumes, %{} = sibling} <- siblings,
        sibling.model.domain == c.model.domain,
        {local, ^consumes} <- Rules.consumed(c.declarations),
        original = original(consumes, local),
        event = Enum.find(sibling.model.events, &(&1.name == original)),
        event != nil,
        into: %{} do
      declared = Enum.find(Rules.local_events(sibling.declarations), &(&1.name == original))
      {local, %{sibling: sibling.module, event: event, at: Links.at(declared)}}
    end
  end

  defp original(consumes, local) do
    renames = if Keyword.keyword?(List.wrap(consumes.as)), do: List.wrap(consumes.as), else: []
    Enum.find(consumes.events, &(Keyword.get(renames, &1, &1) == local))
  end

  defp correlation(c, events) do
    types = local_types(c.model.events)

    for process <- c.declarations.processes,
        include <- process.includes ++ Enum.flat_map(process.stages, & &1.includes),
        consumed = events[include.event],
        consumed != nil,
        field <- process.correlate,
        problem <- problems(consumed, field, types[field]) do
      {"X6: process #{inspect(process.name)} includes #{inspect(include.event)} and correlates " <>
         "on #{inspect(field)}, #{problem}", Links.at(include)}
    end
  end

  defp managers(c, events) do
    for pm <- c.declarations.process_managers,
        model = Enum.find(c.model.process_managers, &(&1.name == pm.name)),
        types = Map.new(model.state.fields, &{&1.name, &1.type}),
        trigger <- pm.starts_on ++ pm.on ++ pm.ends_on,
        consumed = events[trigger.event],
        consumed != nil,
        field <- pm.correlate,
        problem <- problems(consumed, field, types[field]) do
      {"X6: process manager #{inspect(pm.name)} handles #{inspect(trigger.event)} and " <>
         "correlates on #{inspect(field)}, #{problem}", Links.at(trigger)}
    end
  end

  defp matches(c, events) do
    for unit <- c.declarations.units,
        unit.kind == :dcb,
        consults <- unit.consults,
        consumed = events[consults.event],
        consumed != nil,
        field <- consults.match,
        problem <- problems(consumed, field, :id) do
      {"X6: dcb #{inspect(unit.name)} consults #{inspect(consults.event)} matching " <>
         "#{inspect(field)}, #{problem}", Links.at(consults)}
    end
  end

  # The type a field has in this contract's own events, where it has one.
  defp local_types(events) do
    events
    |> Enum.flat_map(& &1.fields)
    |> Enum.reverse()
    |> Map.new(&{&1.name, &1.type})
  end

  defp problems(consumed, field, type) do
    event =
      "event #{inspect(consumed.event.name)} of #{inspect(consumed.sibling)} " <>
        "(#{Links.place(consumed.at)})"

    case Enum.find(consumed.event.fields, &(&1.name == field)) do
      nil ->
        ["which #{event} does not have"]

      %{type: theirs} when type != nil and theirs != type ->
        ["which #{event} has as #{inspect(theirs)}, not #{inspect(type)}"]

      %{optional: true} ->
        [
          "which #{event} declares optional; a field telling which run an event belongs to cannot be"
        ]

      %{personal: personal} when personal != nil ->
        [
          "which #{event} declares personal; a field telling which run an event belongs to cannot be"
        ]

      _ ->
        []
    end
  end
end
