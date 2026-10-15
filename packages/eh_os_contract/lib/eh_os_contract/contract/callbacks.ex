defmodule EhOsContract.Contract.Callbacks do
  # What an implementation of one declaration has to define (v2 §5): the one list the
  # generated behaviour is written from and `EhOsContract.Implementation` checks
  # against, so the two cannot disagree. Its published description, a table per kind
  # with the shapes of a decision and of what a reaction issues, is
  # `EhOsContract.Implementation`'s moduledoc: change it with a callback's shape here.
  #
  # Each callback also says what it may produce, for the implementation macros: a
  # command's callback emits that command's events and rejects on its invariants; a
  # reaction issues what its declaration issues.
  @moduledoc false

  alias EhOsContract.Model

  @typedoc "One callback an implementation defines."
  @type callback :: %{
          name: atom(),
          arity: non_neg_integer(),
          args: [Macro.t()],
          returns: Macro.t(),
          emits: [atom()],
          rejects: [atom()],
          issues: [atom()],
          names: [atom()]
        }

  @typedoc "What an implementation of one declaration defines."
  @type t :: %{
          callbacks: [callback()],
          evolve: nil | %{state: module(), events: [atom()], callback: callback()}
        }

  @doc """
  The callbacks for the declaration `name` of `kind` in the contract `model`. The
  kinds are those of `EhOsContract.Model.module_for/3` that bind an implementation.
  """
  @spec of(map(), atom(), atom()) :: t()
  def of(model, kind, name) when kind in [:aggregate, :dcb] do
    unit = Enum.find(model.units, &(&1.name == name and &1.kind == kind))
    state = Module.concat(Model.module_for(model, kind, name), State)

    commands =
      for c <- model.commands, c.unit == name do
        callback(
          c.name,
          [t(Model.module_for(model, :command, c.name)), t(state)] ++ reads(c),
          decision(),
          emits: c.emits,
          rejects: c.rejects
        )
      end

    # A boundary may consult an event of its own (A4); it is folded once.
    events =
      Enum.uniq(
        for(e <- model.events, e.unit == name, do: e.name) ++ Enum.map(unit.consults, & &1.event)
      )

    %{
      callbacks: commands,
      evolve:
        if(length(unit.state.fields) > length(unit.identity), do: evolve(model, state, events))
    }
  end

  def of(model, :policy, name) do
    policy = Enum.find(model.policies, &(&1.name == name))

    %{
      callbacks:
        for(
          e <- policy.handles,
          do:
            callback(e, [event(model, e)], issued(),
              issues: EhOsContract.Reactions.commands_on(:policy, policy, e)
            )
        ),
      evolve: nil
    }
  end

  def of(model, :effect, name) do
    effect = Enum.find(model.effects, &(&1.name == name))
    returns = quote(do: :ok | {:error, term()})

    %{
      callbacks: for(e <- effect.handles, do: callback(e, [event(model, e)], returns)),
      evolve: nil
    }
  end

  def of(model, :process_manager, name) do
    pm = Enum.find(model.process_managers, &(&1.name == name))
    state = Module.concat(Model.module_for(model, :process_manager, name), State)
    timers = MapSet.new(pm.timers, & &1.name)
    reactions = pm.starts_on ++ pm.on
    issued = EhOsContract.Reactions.issued_by(:process_manager, pm)

    # A callback per event that issues, and one per timer: a timer's own commands first,
    # then those of an `on` naming it.
    on_events = for r <- issued, not EhOsContract.Reactions.timer?(r), do: {r.on, r.command}

    on_timers =
      for(%{trigger: :timer} = r <- issued, do: {r.on, r.command}) ++
        for %{trigger: :on} = r <- issued, EhOsContract.Reactions.timer?(r), do: {r.on, r.command}

    callbacks =
      for(
        {e, issues} <- merge(on_events),
        do: callback(e, [event(model, e), t(state)], issued(), issues: issues)
      ) ++
        for {timer, issues} <- merge(on_timers),
            do: callback(timer, [t(state)], issued(), issues: issues)

    triggers =
      (Enum.map(reactions, & &1.event) ++ pm.ends_on)
      |> Enum.reject(&MapSet.member?(timers, &1))
      |> Enum.uniq()

    declared? = Enum.any?(pm.state.fields, &(&1.name not in pm.correlate))
    %{callbacks: callbacks, evolve: if(declared?, do: evolve(model, state, triggers))}
  end

  def of(model, :read_model, name) do
    read_model = Enum.find(model.read_models, &(&1.name == name))

    %{
      callbacks:
        for(e <- read_model.projects, do: callback(e, [event(model, e)], quote(do: :ok))),
      evolve: nil
    }
  end

  def of(model, :query, name) do
    query = Enum.find(model.queries, &(&1.name == name))
    row = t(Module.concat(Model.module_for(model, :read_model, query.reads), Row))

    returns =
      case query.returns do
        :many -> quote(do: [unquote(row)])
        :one -> quote(do: unquote(row) | nil)
      end

    params = t(Model.module_for(model, :query, name))
    %{callbacks: [callback(name, [params, quote(do: map())], returns)], evolve: nil}
  end

  def of(model, :domain_service, name) do
    service = Enum.find(model.domain_services, &(&1.name == name))
    values = Module.concat(model.domain, Values)
    type = &EhOsContract.Contract.Generate.typespec(&1, values)

    callbacks =
      for f <- service.functions do
        args =
          for a <- f.arguments do
            if a.optional, do: quote(do: unquote(type.(a.type)) | nil), else: type.(a.type)
          end

        returns =
          if f.returns.optional,
            do: quote(do: unquote(type.(f.returns.type)) | nil),
            else: type.(f.returns.type)

        callback(f.name, args, returns, names: Enum.map(f.arguments, & &1.name))
      end

    %{callbacks: callbacks, evolve: nil}
  end

  # `model` is the domain's here: a value belongs to the domain, not to a contract.
  def of(model, :value, name) do
    value = Enum.find(model.values, &(&1.name == name))
    type = quote(do: unquote(Module.concat(model.module, Values)).unquote(name)())

    %{
      callbacks:
        for(
          i <- value.invariants,
          do: callback(i.name, [type], quote(do: boolean()), names: [name])
        ),
      evolve: nil
    }
  end

  # One callback per name: two reactions of one process manager on the same trigger
  # issue into the same callback.
  defp merge(pairs) do
    pairs
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {name, issues} -> {name, issues |> List.flatten() |> Enum.uniq()} end)
    |> Enum.sort_by(fn {name, _} -> Enum.find_index(pairs, &(elem(&1, 0) == name)) end)
  end

  defp evolve(model, state, events) do
    union =
      events
      |> Enum.map(&event(model, &1))
      |> Enum.reverse()
      |> Enum.reduce(fn type, union -> {:|, [], [type, union]} end)

    %{
      state: state,
      events: events,
      callback: callback(:evolve, [t(state), union], t(state))
    }
  end

  defp callback(name, args, returns, produces \\ []) do
    %{
      name: name,
      arity: length(args),
      args: args,
      returns: returns,
      emits: Keyword.get(produces, :emits, []),
      rejects: Keyword.get(produces, :rejects, []),
      issues: Keyword.get(produces, :issues, []),
      # The arguments' names, where the declaration gives them: a domain service's, and
      # a value's check, which takes the value by its name.
      names: Keyword.get(produces, :names, [])
    }
  end

  # Plan DD, T2a (#240): a command that reads entities is decided with them, a third
  # argument holding each row under the name `reads:` gives it.
  defp reads(command) do
    case Map.get(command, :reads, []) do
      [] -> []
      reads -> [{:%{}, [], for({name, _field} <- reads, do: {name, quote(do: map())})}]
    end
  end

  defp event(model, name), do: t(Model.module_for(model, :event, name))
  defp t(module), do: quote(do: unquote(module).t())

  defp decision, do: quote(do: {:ok, [struct()]} | {:error, EhOsContract.Rejection.t()})
  defp issued, do: quote(do: {:ok, [struct()]})
end
