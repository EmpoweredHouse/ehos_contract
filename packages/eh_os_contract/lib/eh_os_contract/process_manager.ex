defmodule EhOsContract.ProcessManager do
  # A process manager steering its runs (v2 §12): fed from the log in order by
  # `EhOsContract.Subscription`, one event a step, each step one transaction.
  #
  # A step takes the run the event belongs to — its correlation values, joined by
  # `EhOsContract.Key` — and its row in `eh_os_contract_process_managers`:
  #
  # - **An event it starts on** starts a run that has no row: its state begins with the
  #   correlation fields. **An event it reacts on** reaches a running run. Anything
  #   else — a reaction for a run that never started, or an event after its end — is
  #   taken and changes nothing.
  # - **The reaction's callback**, when the reaction issues, is called with the event
  #   and the state before it, as `EhOsContract.ScenarioCase` calls it; what it issues
  #   is dispatched at once, as the process manager's actor, keyed
  #   `"pm:<contract id>:<name>:<event id>:<index>"`, so a second delivery appends
  #   nothing. Then `evolve/2` folds the event into the state.
  # - **Timers** are what the reaction declares: `sets:` schedules a
  #   `EhOsContract.TimerJob` — after `wait:` from the event's time, or `at:` a
  #   timestamp of the state — whose token is the event's id, and `cancels:` forgets
  #   the token, so a job already queued finds nothing to fire. **An `ends_on` event**
  #   ends the run and forgets every timer.
  # - **A timer's firing** is an `eh_os_contract.timer_elapsed` event in the run's
  #   stream (`EhOsContract.TimerJob`). A firing whose token is still the run's calls
  #   the timer's callback with the state, applies the `on` reactions to the timer, and
  #   forgets the token; any other firing is ignored, so a timer fired twice dispatches
  #   once.
  #
  # **A run that would start with a key over `EhOsContract.Key.budget/0`** — its timer
  # stream, the manager's key and the correlation escaped — raises
  # `EhOsContract.Key.TooLongError` before anything is written, in place of Postgres
  # refusing the entry: the subscription stops at that event until someone skips it
  # (issue #98). An event no run takes is taken whatever its key's length, as before.
  #
  # **Replay.** A process manager being rebuilt takes the whole log again with its
  # reactions suppressed: states and timers are recomputed, nothing is dispatched and no
  # job is scheduled. At the head of the log every pending timer is scheduled again,
  # once (`TimerJob` is unique on its arguments), and one already due fires at once.
  @moduledoc false

  import Ecto.Query

  alias EhOsContract.{
    Consumer,
    Duration,
    Event,
    Implementations,
    Key,
    LogMetadata,
    Model,
    ProcessManagerRecord,
    TimerJob
  }

  @elapsed "eh_os_contract.timer_elapsed"

  @doc "The type of a timer's firing in the log."
  @spec elapsed() :: String.t()
  def elapsed, do: @elapsed

  @doc "The stream a run's timer firings are appended to."
  @spec stream(String.t(), String.t()) :: String.t()
  def stream(key, correlation), do: "$pm:#{key}:#{correlation}"

  @doc """
  Takes one event of the log for `consumer`, a process manager (see the moduledoc).
  `replay: true` suppresses its reactions.
  """
  @spec handle!(module(), Implementations.consumer(), Event.t(), [String.t()], boolean()) :: :ok
  # What the process manager logs while it takes the event carries the event's correlation (#298).
  def handle!(repo, consumer, %Event{} = row, chain, replay?),
    do:
      LogMetadata.correlated(row.correlation_id, fn ->
        handled!(repo, consumer, row, chain, replay?)
      end)

  defp handled!(repo, consumer, %Event{type: @elapsed} = row, _chain, replay?) do
    %{"process_manager" => key, "correlation" => correlation, "timer" => timer, "token" => fired} =
      row.payload

    with true <- key == consumer.key,
         %ProcessManagerRecord{completed_at: nil} = record <- load(repo, key, correlation),
         %{"token" => ^fired} <- Map.get(record.timers, timer) do
      {model, pm} = declaration(consumer)
      name = String.to_existing_atom(timer)
      state = state!(record)
      source = %{id: row.id, correlation_id: row.correlation_id}

      unless replay? or not exported?(consumer, name, 1) do
        issued = apply(consumer.module, name, [state])
        issue!(consumer, model, pm, name, source, issued, [])
      end

      reactions = Enum.filter(pm.on, &(&1.event == name))
      schedule = unless replay?, do: {key, correlation}
      timers = record.timers |> Map.delete(timer) |> timers(reactions, pm, state, row, schedule)
      save!(repo, record, %{state: state, timers: timers, position: row.position})
    end

    :ok
  end

  defp handled!(repo, consumer, %Event{} = row, chain, replay?) do
    {model, pm} = declaration(consumer)
    event = Consumer.decode!(row)
    name = Map.fetch!(consumer.callbacks, row.type)
    values = Enum.map(pm.correlate, &Map.get(event, &1))

    # An event that does not say which run it belongs to belongs to none.
    if Enum.all?(values, &(&1 != nil)) do
      correlation = Key.join(values)
      record = load(repo, consumer.key, correlation)
      starts? = record == nil and Enum.any?(pm.starts_on, &(&1.event == name))
      running? = record != nil and record.completed_at == nil

      # Only a run that starts writes a new key: an event no run takes is read for
      # nothing, which Postgres answers whatever its length, and a running run's key
      # is already stored.
      if starts?, do: fits!(consumer, correlation, row)

      if starts? or running? do
        step!(repo, consumer, {model, pm}, record, correlation, event, row, chain, replay?)
      end
    end

    :ok
  end

  # The run's timer stream, `"$pm:<key>:<correlation>"`, is the longest key a run
  # writes, longer than its row's `name` and `correlation`: within the budget, both fit.
  # Over it, the run does not start and the subscription stops here, as at any failure,
  # until someone skips the event (issue #98).
  defp fits!(consumer, correlation, row) do
    stream = stream(consumer.key, correlation)

    unless Key.fits?([stream]) do
      raise Key.TooLongError,
            "process manager #{consumer.key} cannot take the event at position " <>
              "#{row.position}: its run's key is #{byte_size(stream)} bytes, over the " <>
              "budget of #{Key.budget()}"
    end
  end

  defp step!(repo, consumer, {model, pm}, record, correlation, event, row, chain, replay?) do
    name = Map.fetch!(consumer.callbacks, row.type)

    state =
      if record,
        do: state!(record),
        else: initial(model, pm, event)

    reactions =
      if record,
        do: Enum.filter(pm.on, &(&1.event == name)),
        else: Enum.filter(pm.starts_on, &(&1.event == name))

    if not replay? and Enum.any?(reactions, &(&1.issues != [])) and exported?(consumer, name, 2) do
      link = "#{Model.fetch(consumer.contract).id}:#{consumer.name}:#{row.type}"

      if link in chain do
        raise ArgumentError,
              "process manager #{inspect(consumer.name)} of #{inspect(consumer.contract)} reacts " <>
                "to #{row.type} again down one chain of dispatches, which would never end: " <>
                "#{inspect(Enum.reverse([link | chain]))}"
      end

      issued = apply(consumer.module, name, [event, state])
      source = %{id: row.id, correlation_id: row.correlation_id}
      issue!(consumer, model, pm, name, source, issued, [link | chain])
    end

    state =
      if exported?(consumer, :evolve, 2), do: consumer.module.evolve(state, event), else: state

    record = record || %ProcessManagerRecord{name: consumer.key, correlation: correlation}

    schedule = unless replay?, do: {consumer.key, correlation}

    {timers, completed_at} =
      if name in pm.ends_on,
        do: {%{}, row.occurred_at},
        else: {timers(record.timers || %{}, reactions, pm, state, row, schedule), nil}

    save!(repo, record, %{
      state: state,
      timers: timers,
      position: row.position,
      completed_at: completed_at
    })
  end

  defp issue!(consumer, model, pm, name, source, issued, chain) do
    issues = EhOsContract.Reactions.commands_on(:process_manager, pm, name)

    commands =
      case issued do
        {:ok, commands} -> commands
        other -> other
      end

    Consumer.issue!(consumer, :pm, source, commands, {model, issues}, chain)
  end

  # What the reactions set and cancel, applied to the run's pending timers. A timer
  # set again replaces the one pending, whose job then finds another token.
  # `schedule` is the run's key and correlation, or nil in a replay, which schedules
  # nothing until the head.
  defp timers(timers, reactions, pm, state, row, schedule) do
    Enum.reduce(reactions, timers, fn reaction, timers ->
      timers = Map.drop(timers, Enum.map(Map.get(reaction, :cancels, []), &Atom.to_string/1))

      Enum.reduce(reaction.sets, timers, fn name, timers ->
        timer = Enum.find(pm.timers, &(&1.name == name))

        entry = %{
          "token" => row.id,
          "at" => DateTime.to_iso8601(fires_at(timer, state, row)),
          "correlation_id" => row.correlation_id
        }

        with {key, correlation} <- schedule,
             do: schedule!(key, correlation, name, entry)

        Map.put(timers, Atom.to_string(name), entry)
      end)
    end)
  end

  defp fires_at(%{wait: %{amount: n, unit: unit}}, _state, row),
    do: Duration.calendar_shift(row.occurred_at, {n, unit})

  defp fires_at(%{at: field, name: name}, state, _row) do
    case Map.fetch!(state, field) do
      %DateTime{} = at ->
        at

      nil ->
        raise ArgumentError,
              "timer #{inspect(name)} fires at the state's #{inspect(field)}, which is nil when " <>
                "the timer is set"
    end
  end

  defp schedule!(key, correlation, name, entry),
    do: {:ok, _} = Oban.insert(TimerJob.job(key, correlation, Atom.to_string(name), entry))

  @doc """
  Schedules the pending timers of every running run of `consumer` after a replay,
  and returns how many. A job already queued for a timer is left to fire, and is not
  duplicated. **A timer that came due with no job queued is dropped**: it came due
  while nothing steered the run — before this process manager was deployed — and
  firing it now would act on history. After a rebuild of one that was running, a
  timer still due has its job queued from before, and fires.
  """
  @spec reconcile!(module(), Implementations.consumer()) :: non_neg_integer()
  def reconcile!(repo, consumer) do
    now = EhOsContract.Clock.now()

    records =
      repo.all(
        from(r in ProcessManagerRecord, where: r.name == ^consumer.key and is_nil(r.completed_at))
      )

    for record <- records, reduce: 0 do
      n ->
        {kept, dropped} =
          Enum.split_with(record.timers, fn {timer, entry} ->
            {:ok, at, _} = DateTime.from_iso8601(entry["at"])
            DateTime.compare(at, now) == :gt or queued?(repo, consumer.key, record, timer, entry)
          end)

        if dropped != [] do
          repo.update_all(
            from(r in ProcessManagerRecord,
              where: r.name == ^record.name and r.correlation == ^record.correlation
            ),
            set: [timers: Map.new(kept)]
          )
        end

        for {timer, entry} <- kept do
          {:ok, _} = Oban.insert(TimerJob.job(consumer.key, record.correlation, timer, entry))
        end

        n + length(kept)
    end
  end

  # A job not yet finished for exactly this timer: the one its run queued before.
  defp queued?(repo, key, record, timer, entry) do
    args = TimerJob.job(key, record.correlation, timer, entry).changes.args

    # Where Oban's `prefix:` puts its jobs, as `EhOsContract.Paths` reads them.
    repo.exists?(
      from(j in Oban.Job,
        prefix: ^Oban.config().prefix,
        where:
          j.worker == "EhOsContract.TimerJob" and
            j.state in ["available", "scheduled", "executing", "retryable", "suspended"] and
            fragment("? @> ?", j.args, ^args)
      )
    )
  end

  @doc "Forgets every run of `consumer`, before a replay rebuilds them."
  @spec reset!(module(), Implementations.consumer()) :: :ok
  def reset!(repo, consumer) do
    repo.delete_all(from(r in ProcessManagerRecord, where: r.name == ^consumer.key))
    :ok
  end

  defp initial(model, pm, event) do
    struct(
      Module.concat(Model.module_for(model, :process_manager, pm.name), State),
      Map.new(pm.correlate, &{&1, Map.fetch!(event, &1)})
    )
  end

  # `:safe`: the state is the engine's own struct, whose atoms exist; a binary that
  # would create an atom or a fun was not written by the engine and is refused.
  defp state!(record), do: :erlang.binary_to_term(record.state, [:safe])

  defp load(repo, key, correlation),
    do: repo.get_by(ProcessManagerRecord, name: key, correlation: correlation)

  defp save!(repo, record, changes) do
    row = %{
      name: record.name,
      correlation: record.correlation,
      state: :erlang.term_to_binary(changes.state),
      timers: changes.timers,
      position: changes.position,
      completed_at: Map.get(changes, :completed_at, record.completed_at)
    }

    repo.insert_all(ProcessManagerRecord, [row],
      on_conflict: {:replace, [:state, :timers, :position, :completed_at]},
      conflict_target: [:name, :correlation]
    )

    :ok
  end

  defp declaration(consumer) do
    model = Model.fetch(consumer.contract)
    {model, Enum.find(model.process_managers, &(&1.name == consumer.name))}
  end

  defp exported?(%{module: nil} = consumer, _name, _arity) do
    raise ArgumentError,
          "process manager #{inspect(consumer.name)} of #{inspect(consumer.contract)} takes events " <>
            "and no module implements it; bind one with " <>
            "`use #{inspect(consumer.contract)}, process_manager: #{inspect(consumer.name)}`"
  end

  defp exported?(%{module: module}, name, arity), do: function_exported?(module, name, arity)
end
