defmodule EhosContract.Contract.Links.System do
  # X7, X8 and the part of D14 no single contract can check: names that have to be
  # unique across the application, and one implementation per declaration.
  #
  # - **X7.** A process module's `id:` is unique across the application: it keys the
  #   process's runs (plan DD, P2c, #210), so two processes of one id would share runs
  #   no reader could tell apart. It may equal a contract's `id:`: that one prefixes
  #   event types, which are never a run's key.
  #   So is a contract's `id:` (plan DD, ID1), which prefixes every event type the
  #   contract records (`"<id>.<event>"`, from ID3).
  # - **X8.** A declaration that code implements — a unit, a policy, an effect, a
  #   process manager, a read model, a query — has at most one implementation, since
  #   dispatch and scenarios have to know which one runs.
  # - **D14.** A command's, a query's or a recorded event's name is unique across
  #   the contracts of one domain: its capability is `<domain>.<name>`, which EHOS
  #   grants by, so two declarations of one name would share it.
  #
  # Of two declarations that collide, the error stands at the one in the module
  # that sorts later and names the other with its file and line.
  @moduledoc false

  alias EhosContract.Contract.{Links, Rules}

  @doc false
  @spec check(map()) :: [Links.violation()]
  def check(system),
    do: processes(system) ++ ids(system) ++ capabilities(system) ++ implementations(system)

  defp processes(system) do
    # Sorted by module, and the later is refused.
    named =
      system.processes
      |> Enum.map(&{&1.model.id, &1.module, {&1.model.id, &1.at}})
      |> Enum.sort_by(&inspect(elem(&1, 1)))

    for {_key, {module, {name, at}}, {first, {_first_name, first_at}}} <- collisions(named) do
      {"X7: process #{inspect(name)} of #{inspect(module)} is also declared by " <>
         "#{inspect(first)} (#{Links.place(first_at)}); a process's name keys its runs, so it " <>
         "is unique in the application", at}
    end
  end

  defp ids(system) do
    named =
      for %{id: %{value: id, at: at}} = c <- system.contracts,
          do: {id, c.module, at}

    for {id, {module, at}, {first, first_at}} <- collisions(named) do
      {"X7: the id: #{inspect(id)} of #{inspect(module)} is also the id: of #{inspect(first)} " <>
         "(#{Links.place(first_at)}); a contract's id prefixes its event types, so it is " <>
         "unique in the application", at}
    end
  end

  defp capabilities(system) do
    named =
      for %{domain: %{name: domain}} = c <- system.contracts,
          {kind, declaration} <-
            Enum.map(Rules.commands(c.declarations), &{:command, &1}) ++
              Enum.map(c.declarations.queries, &{:query, &1}) ++
              Enum.map(recorded(c.declarations), &{:record, &1}) do
        {"#{domain}.#{declaration.name}", c.module, {kind, declaration}}
      end

    for {capability, {module, {kind, declaration}}, {first, {first_kind, first_declaration}}} <-
          collisions(named),
        module != first or kind != first_kind do
      {"D14: #{kind} #{inspect(declaration.name)} of #{inspect(module)} has the capability " <>
         "#{inspect(capability)}, which #{first_kind} #{inspect(first_declaration.name)} of " <>
         "#{inspect(first)} (#{Links.place(Links.at(first_declaration))}) has already; a " <>
         "command, a query or a recorded event is named once in the domain",
       Links.at(declaration)}
    end
  end

  defp recorded(declarations) do
    for unit <- declarations.units,
        event <- unit.events,
        event.recorded_by != [],
        do: event
  end

  defp implementations(system) do
    named =
      for impl <- system.implementations do
        {{impl.contract, impl.kind, impl.name}, impl.module, use_at(impl)}
      end

    for {{contract, kind, name}, {module, at}, {first, first_at}} <- collisions(named) do
      {"X8: #{inspect(module)} implements #{human(kind)} #{inspect(name)} of " <>
         "#{inspect(contract)}, which #{inspect(first)} (#{Links.place(first_at)}) implements " <>
         "already; a declaration has one implementation", at}
    end
  end

  # Where the implementation's `use` is. One compiled before the description said so
  # has no place, and is refused all the same.
  defp use_at(%{file: file, line: line}), do: [file: String.to_charlist(file), location: line]
  defp use_at(_description), do: nil

  # For every key held more than once, each holder after the first, with the first.
  # Holders come sorted by module, and within a module in declaration order.
  defp collisions(named) do
    named
    |> Enum.group_by(&elem(&1, 0), &{elem(&1, 1), elem(&1, 2)})
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.flat_map(fn {key, [first | again]} ->
      for other <- again, do: {key, other, first}
    end)
  end

  defp human(kind), do: kind |> Atom.to_string() |> String.replace("_", " ")
end
