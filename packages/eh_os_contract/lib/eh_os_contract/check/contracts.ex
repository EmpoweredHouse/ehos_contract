defmodule EhOsContract.Check.Contracts do
  @moduledoc """
  The rules of `mix eh_os_contract.check` v1 contracts had, over v2 contracts, and
  one only an implementation can answer (v2 §6, L5, "kept from v1" and "new"; plan
  EL1).

  - `backward-edge` — a reaction that issues a command whose events sit in an
    earlier stage than the event it reacts to.
  - `competing-in-transaction-consumers` — an event two or more policies or effects
    react to inside the emitting transaction.
  - `free-text-not-personal` — a `:string` field of an event not marked personal.
  - `emits-never-produced` — an event a command `emits:` that no `emit/1` of its
    implementation names.

  v1's `promise-finer-than-run` is not repeated: a v2 run is keyed by its
  `correlate`, R2 puts those fields in every event of the run, and how a promise
  over a finer unit is evaluated has no v2 contract to be asked on until the
  sandbox's are written anew (E9).
  """

  alias EhOsContract.Check.Finding
  alias EhOsContract.Model
  alias EhOsContract.Next.Contract.{Callbacks, Links, Rules}

  @doc """
  Every finding of these rules about `contracts`, v2 contract modules. Their
  implementations are the ones dispatch finds (`EhOsContract.Implementations`),
  unless `implementations` names the modules to read instead.
  """
  @spec findings([module()], [module()] | nil) :: [Finding.t()]
  def findings(contracts, implementations \\ nil) do
    linked = contracts |> Enum.map(&Links.contract/1) |> Enum.reject(&is_nil/1)

    competing(linked) ++
      Enum.flat_map(linked, fn c ->
        backward(c) ++ free_text(c) ++ never_emitted(c, implemented(c.module, implementations))
      end)
  end

  # `{contract, kind, name} => [module]`, as `EhOsContract.Implementations.index/1` has it.
  defp implemented(contract, nil), do: EhOsContract.Implementations.index(contract).declarations

  defp implemented(_contract, modules) do
    Enum.group_by(
      modules,
      fn module ->
        %{contract: contract, kind: kind, name: name} = module.__eh_os_implementation__()
        {contract, kind, name}
      end
    )
  end

  defp at(declarations, name) do
    case Enum.find(declarations, &(&1.name == name)) do
      nil -> nil
      declaration -> Links.at(declaration)
    end
  end

  # What each reaction of a contract reacts to and what it issues: a policy, and a
  # process manager's start, reactions and timers' firings.
  defp reactions(model) do
    for(p <- model.policies, e <- List.wrap(p.handles), do: {:policy, p.name, e, p.issues}) ++
      Enum.flat_map(model.process_managers, fn pm ->
        for(s <- pm.starts_on, do: {:process_manager, pm.name, s.event, s.issues}) ++
          for o <- pm.on, do: {:process_manager, pm.name, o.event, o.issues}
      end)
  end

  # The stage an event sits in for this contract's process: its own, or the one the
  # process gives a consumed event it includes. `nil` when it has none.
  defp stage_of(model, event) do
    case Enum.find(model.events, &(&1.name == event)) do
      %{stage: stage} ->
        stage

      nil ->
        model.process &&
          Enum.find_value(model.process.includes, &(&1.event == event && &1.stage))
    end
  end

  defp backward(%{model: %{process: %{stages: [_, _ | _] = stages}} = model} = c) do
    order = stages |> Enum.map(& &1.name) |> Enum.with_index() |> Map.new()

    for {kind, name, event, issues} <- reactions(model),
        from = order[stage_of(model, event)],
        from != nil,
        command <- List.wrap(issues),
        %{} = issued <- [Enum.find(model.commands, &(&1.name == command))],
        into <- issued.emits,
        to = order[stage_of(model, into)],
        to != nil and to < from,
        uniq: true do
      declarations =
        if kind == :policy, do: c.declarations.policies, else: c.declarations.process_managers

      Finding.new(
        "backward-edge",
        "#{kind} #{inspect(name)} of #{inspect(model.module)} reacts to #{inspect(event)} in stage " <>
          "#{inspect(stage_of(model, event))} and issues #{inspect(command)}, whose " <>
          "#{inspect(into)} is in the earlier stage #{inspect(stage_of(model, into))}",
        at(declarations, name)
      )
    end
  end

  defp backward(_contract), do: []

  # v1's `competing-sync-handlers`: several reactions in one transaction, to one
  # event, in an order the contract does not state. A read model is not counted: it
  # projects, and decides nothing another reaction could depend on.
  defp competing(linked) do
    reactions =
      for %{model: model} = c <- linked,
          {kind, declarations} <- [policy: model.policies, effect: model.effects],
          declaration <- declarations,
          declaration.delivery == :in_transaction,
          event <- List.wrap(declaration.handles),
          {publisher, %{name: original}} <- [declaring(model, event)] do
        {{publisher, original},
         "#{kind} #{inspect(declaration.name)} of #{inspect(model.module)}", c}
      end

    for {{publisher, event}, [_, _ | _] = group} <- Enum.group_by(reactions, &elem(&1, 0)) do
      names = group |> Enum.map(&elem(&1, 1)) |> Enum.sort()
      {_, _, first} = Enum.min_by(group, &elem(&1, 1))

      Finding.new(
        "competing-in-transaction-consumers",
        "#{inspect(event)} of #{inspect(publisher)} has #{length(names)} reactions inside the " <>
          "transaction that records it — #{Enum.join(names, ", ")} — and nothing says which " <>
          "comes first. If one depends on the other, have it react to what the other decides",
        first.at
      )
    end
  end

  # The contract and declaration of an event a contract takes, or `nil`. A consumed
  # contract nobody compiled is X5's to report; `Model.declaring/2` would raise on it
  # and take every other finding with it.
  defp declaring(model, event) do
    case Model.consumed(model, event) do
      {:contract, from, _original} -> if Links.contract(from), do: Model.declaring(model, event)
      _local_or_received -> Model.declaring(model, event)
    end
  end

  # v1's `free-text-without-retain`, in v2's words: `:string` is text a person typed,
  # and unless it is personal, it stays in the log verbatim even after its subject
  # is erased (v2 §14).
  defp free_text(%{model: model} = c) do
    for event <- model.events,
        field <- event.fields,
        field.type == :string,
        field.personal == nil do
      at =
        with %{} = unit <- Enum.find(c.declarations.units, &(&1.name == event.unit)),
             %{} = declared <- Enum.find(Rules.events(unit), &(&1.name == event.name)),
             do: at(declared.fields, field.name)

      Finding.new(
        "free-text-not-personal",
        "#{inspect(event.name)}.#{field.name} of #{inspect(model.module)} is free text and not " <>
          "`personal:`, so it stays in the log as written, whoever it is about",
        at
      )
    end
  end

  # An event a command may emit that its implementation never names in `emit/1`:
  # declared, and no path of the code produces it. Events emitted in a function that
  # is no command's callback count for every command, since nothing says which one
  # calls it.
  defp never_emitted(%{model: model} = c, declarations) do
    for unit <- model.units,
        [implementation] <- [Map.get(declarations, {model.module, unit.kind, unit.name})],
        %{emitted: emitted} = implementation.__eh_os_implementation__(),
        callbacks = Callbacks.of(model, unit.kind, unit.name).callbacks,
        shared =
          for(
            {function, names} <- emitted,
            not Enum.any?(callbacks, &({&1.name, &1.arity} == function)),
            name <- names,
            do: name
          ),
        callback <- callbacks,
        produced = Map.get(emitted, {callback.name, callback.arity}, []) ++ shared,
        event <- callback.emits,
        event not in produced do
      command_at =
        with %{} = declared <- Enum.find(c.declarations.units, &(&1.name == unit.name)),
             do: at(declared.commands, callback.name)

      Finding.new(
        "emits-never-produced",
        "command #{inspect(callback.name)} of #{inspect(model.module)} may emit " <>
          "#{inspect(event)}, and no emit/1 in #{inspect(implementation)} names it",
        command_at
      )
    end
  end
end
