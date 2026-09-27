defmodule EhOsContract.Next.Contract.Callbacks do
  @moduledoc """
  What an implementation of one declaration has to define (v2 §5): the one list the
  generated behaviour is written from and `EhOsContract.Implementation` checks
  against, so the two cannot disagree.

  | Kind | Callbacks |
  | --- | --- |
  | aggregate, dcb | one per command, `(command, state) :: decision`; `evolve/2` when the unit declares a state |
  | policy | one per handled event, `(event) :: issued` |
  | effect | one per handled event, `(event) :: :ok \\| {:error, term}` |
  | process manager | one per starting or running reaction that issues, `(event, state) :: issued`; one per timer that issues, `(state) :: issued`; `evolve/2` when it declares a state |
  | read model | one per projected event, `(event) :: :ok` |
  | query | one, named after it, `(params, ctx) :: rows` |
  | domain service | one per function, `(arguments…) :: result`, typed as declared |

  A decision is `{:ok, [event]}` or `{:error, %EhOsContract.Rejection{}}`; what is
  issued is `{:ok, [command]}`. `evolve/2` folds the events a state is kept from: a
  unit's own, a boundary's consulted ones too, and a process manager's triggers.

  Each callback also says what it may produce, for the implementation macros: a
  command's callback emits that command's events and rejects on its invariants; a
  reaction issues what its declaration issues.
  """

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
        callback(c.name, [t(Model.module_for(model, :command, c.name)), t(state)], decision(),
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
          do: callback(e, [event(model, e)], issued(), issues: policy.issues)
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

    on_events =
      for r <- reactions, r.issues != [], not MapSet.member?(timers, r.event) do
        {r.event, r.issues}
      end

    on_timers =
      for(t <- pm.timers, t.issues != [], do: {t.name, t.issues}) ++
        for(
          r <- reactions,
          r.issues != [],
          MapSet.member?(timers, r.event),
          do: {r.event, r.issues}
        )

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
    type = &EhOsContract.Next.Contract.Generate.typespec(&1, values)

    callbacks =
      for f <- service.functions do
        args =
          for a <- f.arguments do
            if a.optional, do: quote(do: unquote(type.(a.type)) | nil), else: type.(a.type)
          end

        callback(f.name, args, type.(f.returns), names: Enum.map(f.arguments, & &1.name))
      end

    %{callbacks: callbacks, evolve: nil}
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
      # The arguments' names, where the declaration gives them: a domain service's.
      names: Keyword.get(produces, :names, [])
    }
  end

  defp event(model, name), do: t(Model.module_for(model, :event, name))
  defp t(module), do: quote(do: unquote(module).t())

  defp decision, do: quote(do: {:ok, [struct()]} | {:error, EhOsContract.Rejection.t()})
  defp issued, do: quote(do: {:ok, [struct()]})
end
