defmodule EhOsContract.Paths do
  @moduledoc """
  The declared paths of a v2 contract, and what the log says about each (v2 §13,
  plan E7c).

  A contract makes the command a node of its own, so a path is one **step** of
  these kinds:

  | Step | from | via | to |
  | --- | --- | --- | --- |
  | a command emits | the command | — | the event |
  | a reaction issues | the event | the policy or process manager | the command |
  | a policy issues on a received event | another application's event | the policy | the command |
  | a timer issues | the timer | the process manager | the command |
  | an effect acts | the event | the effect | — |

  Each end is `%{kind, name, label}`, which is what `EhOsContract.Conformance`
  hands on as `conformance.v3`, and what the graph draws.

  ## Taken, waiting, failing

  **Taken** is counted in occurrences, whatever run, if any, each falls in (plan DD,
  P1a, #183): a step is the contract's, which may have no process. A command emitted an event when the event's
  row names the command's row (`command_id`); a reaction issued a command when a row
  of `eh_os_contract_commands` names its actor and, as its cause, an event of the
  step's type. Another application's event never enters this log (D12): a policy on
  it issued a command when the row names, as its cause, a row of
  `eh_os_contract_inbox` that the policy's inbox took, bounded by when it took it.
  Such a step is never failing or waiting: a delivery its policy fails on is rolled
  back and delivered again by the transport, and leaves nothing here, so a path that
  always fails reads as untraversed (#65).
  An effect leaves nothing in the log when it acts, so whether it was
  taken is not known, and its `taken` is `nil`: never untraversed, only waiting or
  failing.

  **Waiting** — "not yet", never "never" — has three sources, each counted apart
  because each goes to a different person: events an ordered consumer has not
  reached yet (`lag`), timers scheduled and not fired (`timers`), and effect jobs
  not run yet (`effects`).

  **Failing** has three too: commands that failed where the step runs, attributed
  through the row's `failed_in` (`commands`, each failed command once); the consumer's subscription
  stopped at an event it cannot apply (`subscription`); effect jobs Oban discarded
  (`effects`). A command that failed in its decision, or in a read model's
  projection, fails every step it emits: which of them it would have taken is not
  known.
  """

  import Ecto.Query

  alias EhOsContract.{
    Codec,
    CommandRecord,
    Consumer,
    Event,
    EventRun,
    InboxRecord,
    Model,
    ProcessManager,
    SubscriptionRecord
  }

  @waiting ~w(available scheduled executing retryable)

  @typedoc "One end of a step, or the consumer it runs through."
  @type node_ref :: %{kind: atom(), name: atom(), label: String.t() | nil}

  @typedoc "One declared step, with what the log says about it."
  @type step :: %{
          from: node_ref(),
          via: node_ref() | nil,
          to: node_ref() | nil,
          mode: :inline | :async,
          taken: non_neg_integer() | nil,
          in_flight: %{
            effects: non_neg_integer(),
            timers: non_neg_integer(),
            lag: non_neg_integer()
          },
          failing: %{
            commands: non_neg_integer(),
            subscription: %{stopped_at: pos_integer(), failure: String.t() | nil} | nil,
            effects: non_neg_integer()
          }
        }

  @doc """
  Every step `contract` declares, in declaration order: its commands' emits, then its
  policies, process managers and effects. `opts`: `:since` and `:until` bound the
  events counted as taken, as in `EhOsContract.Trace`.

  `phases: true` also splits, by phase, the step of a process manager that issues one
  command on one event both as the event starts a run (`starts_on`) and during it
  (`on`) — one step to the report, two relations to the graph: such a step gets
  `phases`, `%{start: %{runs, in_flight}, run: %{runs, in_flight}}`, each issued
  command and each event still waiting counted in the phase
  `EhOsContract.ProcessManager.take/3` gives its event over the log before it. Only
  the runs and the events waiting are split; what fails is the manager's, and stays
  whole. A run that issues the command at its start and again during it counts in
  both, so the phases need not add up to the step. Without the option every step is
  as the report reads it.
  """
  @spec observe(module() | map(), keyword()) :: [step()]
  def observe(contract, opts \\ []) do
    model = Model.fetch(contract)
    steps = steps(model)
    emitted = emitted(model, opts)
    issued = Map.merge(issued(model, opts), received(model, steps, opts))
    lag = lag(steps)
    keys = for %{key: key} <- steps, uniq: true, do: key
    timers = scheduled_timers(keys)
    {waiting_effects, discarded_effects} = effect_jobs(keys)
    failed = failed_commands(model, opts)
    stopped = stopped_subscriptions(steps)
    phased = if opts[:phases], do: phases(model, opts), else: %{}

    for step <- steps do
      key = step[:key]

      step
      |> Map.merge(%{
        taken: taken(step, emitted, issued),
        in_flight: %{
          effects: Map.get(waiting_effects, {key, step.from_type}, 0),
          timers: Map.get(timers, {key, timer_name(step)}, 0),
          lag: Map.get(lag, {key, step.from_type, timer_name(step)}, 0)
        },
        failing: %{
          commands: failed_in_step(step, failed),
          subscription: if(step[:inbox], do: nil, else: Map.get(stopped, key)),
          effects: Map.get(discarded_effects, {key, step.from_type}, 0)
        }
      })
      |> phased(phased)
      |> Map.drop([:key, :from_type, :command_type, :issued_by, :inbox])
    end
  end

  defp phased(%{via: %{kind: :process_manager, name: pm}, from: %{kind: :event}} = step, phased) do
    case Map.fetch(phased, {pm, step.from.name, step.command_type}) do
      {:ok, %{runs: runs, lag: lag}} ->
        Map.put(
          step,
          :phases,
          Map.new([:start, :run], fn phase ->
            {phase,
             %{
               runs: Map.get(runs, phase, 0),
               in_flight: %{step.in_flight | lag: Map.get(lag, phase, 0)}
             }}
          end)
        )

      :error ->
        step
    end
  end

  defp phased(step, _phased), do: step

  @doc """
  The steps `contract` declares, without the log: `from`, `via`, `to` and `mode`,
  in declaration order.
  """
  @spec declared(module() | map()) :: [map()]
  def declared(contract) do
    contract
    |> Model.fetch()
    |> steps()
    |> Enum.map(&Map.take(&1, [:from, :via, :to, :mode]))
  end

  # The declared steps with what `observe/2` needs to find their rows: the consumer's
  # key, the stored type a step starts from, the command's name and its issuer's label.
  defp steps(model) do
    label = labels(model)

    emits =
      for command <- model.commands, event <- command.emits do
        %{
          from: ref(:command, command.name, command.label),
          via: nil,
          to: ref(:event, event, label.(event)),
          mode: :inline,
          from_type: nil,
          command_type: Atom.to_string(command.name)
        }
      end

    policies =
      for policy <- model.policies,
          event <- policy.handles,
          type = type_of(model, event),
          type != nil,
          command <- policy.issues do
        reaction(model, :policy, policy, event, type, command, label)
      end

    # Another application's event, which has no stored type here: taken through its inbox.
    received =
      for policy <- model.policies,
          event <- policy.handles,
          match?({:published, _fields}, Model.consumed(model, event)),
          command <- policy.issues do
        %{
          from: ref(:event, event, nil),
          via: ref(:policy, policy.name, policy.label),
          to: ref(:command, command, command_label(model, command)),
          mode: :async,
          key: key(model, :policy, policy.name),
          from_type: nil,
          inbox: key(model, :inbox, event),
          issued_by: "policy:#{policy.name}",
          command_type: Atom.to_string(command)
        }
      end

    managers =
      for pm <- model.process_managers,
          {event, commands} <- reactions(pm),
          type = type_of(model, event),
          type != nil,
          command <- commands do
        reaction(model, :process_manager, pm, event, type, command, label)
      end

    timers =
      for pm <- model.process_managers, timer <- pm.timers, command <- timer.issues do
        %{
          from: ref(:timer, timer.name, timer.label),
          via: ref(:process_manager, pm.name, pm.label),
          to: ref(:command, command, command_label(model, command)),
          mode: :async,
          key: key(model, :process_manager, pm.name),
          from_type: ProcessManager.elapsed(),
          issued_by: "pm:#{pm.name}",
          command_type: Atom.to_string(command)
        }
      end

    effects =
      for effect <- model.effects,
          event <- effect.handles,
          type = type_of(model, event),
          type != nil do
        %{
          from: ref(:event, event, label.(event)),
          via: ref(:effect, effect.name, effect.label),
          to: nil,
          mode: mode(effect.delivery),
          key: key(model, :effect, effect.name),
          from_type: type
        }
      end

    emits ++ policies ++ received ++ managers ++ timers ++ effects
  end

  @doc """
  What happened in the contract in the period: its events, and its commands, whatever
  their outcome — one that failed was attempted (plan DD, P1a, #183). A step's own
  count is bounded by its cause's time, these by their own, so the two can disagree
  at a period's edge.
  """
  @spec activity(map(), keyword()) :: %{
          events: non_neg_integer(),
          commands: non_neg_integer()
        }
  def activity(model, opts \\ []) do
    events =
      from(e in Event, as: :event, where: e.contract == ^model.id, select: count())
      |> bounded(opts)
      |> repo().one()

    commands =
      from(c in CommandRecord,
        where: c.contract == ^model.id,
        select: count()
      )
      |> bounded_rows(opts)
      |> repo().one()

    %{events: events, commands: commands}
  end

  @doc """
  Distinct runs of the contract's process in the period, over its own events' types
  and the ones it includes. A process's own count: a step is counted in occurrences,
  not runs (plan DD, P1a, #183).
  """
  @spec runs_of(map(), String.t(), keyword()) :: non_neg_integer()
  def runs_of(model, process, opts \\ []) do
    types = Enum.map(Model.process_events(model), & &1.type)

    from(r in EventRun,
      join: e in Event,
      as: :event,
      on: e.position == r.position,
      where: r.process == ^process and e.type in ^types,
      select: count(r.instance_id, :distinct)
    )
    |> bounded(opts)
    |> repo().one()
  end

  @doc """
  How often each event the contract records, and each its process includes, happened
  in the period: `%{name => occurrences}`, by the name the event has in this contract,
  whatever run, if any, it falls in (plan DD, P1a, #183). A contract with no process
  counts its own events; an included event its sibling does not declare is left out.
  """
  @spec occurrences(map(), keyword()) :: %{atom() => non_neg_integer()}
  def occurrences(model, opts \\ []) do
    by_type =
      Map.new(model.events, &{&1.type, &1.name})
      |> Map.merge(
        for(%{included: true} = e <- Model.process_events(model), into: %{}, do: {e.type, e.name})
      )

    types = Map.keys(by_type)

    from(e in Event,
      as: :event,
      where: e.type in ^types,
      group_by: e.type,
      # `position`, not `id`: the `(type, position)` index answers it alone.
      select: {e.type, count(e.position)}
    )
    |> bounded(opts)
    |> repo().all()
    |> Map.new(fn {type, count} -> {Map.fetch!(by_type, type), count} end)
  end

  # --- declarations --------------------------------------------------------------------

  defp reaction(model, kind, consumer, event, type, command, label) do
    %{
      from: ref(:event, event, label.(event)),
      via: ref(kind, consumer.name, consumer.label),
      to: ref(:command, command, command_label(model, command)),
      mode: mode(consumer.delivery),
      key: key(model, kind, consumer.name),
      from_type: type,
      issued_by: "#{if kind == :policy, do: "policy", else: "pm"}:#{consumer.name}",
      command_type: Atom.to_string(command)
    }
  end

  # What each event a process manager takes issues: `starts_on` and `on`, in order.
  defp reactions(pm) do
    for reaction <- pm.starts_on ++ pm.on,
        reaction.issues != [],
        do: {reaction.event, reaction.issues}
  end

  defp ref(kind, name, label), do: %{kind: kind, name: name, label: label}

  defp mode(:in_transaction), do: :inline
  defp mode(_at_least_once), do: :async

  defp key(model, kind, name), do: "#{model.id}:#{kind}:#{name}"

  # An event's label, from the contract that declares it; a sibling's for a consumed one.
  defp labels(model) do
    fn name ->
      case Model.declaring(model, name) do
        {_contract, event} -> event.label
        nil -> nil
      end
    end
  end

  defp type_of(model, name) do
    case Model.declaring(model, name) do
      {_contract, %{type: type}} -> type
      nil -> nil
    end
  end

  defp command_label(model, name) do
    case Enum.find(model.commands, &(&1.name == name)) do
      %{label: label} -> label
      nil -> nil
    end
  end

  defp timer_name(%{from: %{kind: :timer, name: name}}), do: Atom.to_string(name)
  defp timer_name(_step), do: nil

  # --- taken -------------------------------------------------------------------------

  defp taken(%{via: %{kind: :effect}}, _emitted, _issued), do: nil

  defp taken(%{via: nil} = step, emitted, _issued),
    do: Map.get(emitted, {step.command_type, type(step.to)}, 0)

  defp taken(%{from: %{kind: :timer, name: timer}} = step, _emitted, issued),
    do:
      Map.get(
        issued,
        {step.issued_by, step.command_type, step.from_type, Atom.to_string(timer)},
        0
      )

  defp taken(%{inbox: inbox} = step, _emitted, issued),
    do: Map.get(issued, {step.issued_by, step.command_type, {:inbox, inbox}, nil}, 0)

  defp taken(step, _emitted, issued),
    do: Map.get(issued, {step.issued_by, step.command_type, step.from_type, nil}, 0)

  defp type(%{kind: :event, name: name}), do: name

  # Events of the step's type a command of the step's type appended: each one an
  # occurrence, whatever run, if any, it belongs to (plan DD, P1a, #183).
  defp emitted(model, opts) do
    names = Map.new(model.events, &{&1.type, &1.name})

    from(e in Event,
      as: :event,
      join: c in CommandRecord,
      on: c.id == e.command_id,
      where: e.contract == ^model.id and c.contract == ^model.id,
      group_by: [c.type, e.type],
      select: {c.type, e.type, count(e.id)}
    )
    |> bounded(opts)
    |> repo().all()
    |> Map.new(fn {command, type, taken} -> {{command, Map.get(names, type)}, taken} end)
  end

  # A reaction's commands, accepted or rejected, caused by an event of the step's type;
  # for a timer, by its firing. One row is one occurrence: a redelivery the idempotency
  # key turns away writes none (plan DD, P1a, #183).
  # A timer's firing names its timer in the payload; any other event's payload is the
  # domain's, whose own `timer` field would split the count, so it is read only there.
  defp issued(model, opts) do
    elapsed = ProcessManager.elapsed()

    reactions =
      from(c in CommandRecord,
        join: e in Event,
        as: :event,
        on: e.id == c.causation_event_id,
        where: c.contract == ^model.id,
        where: c.outcome in ["accepted", "rejected"],
        where: like(c.issued_by, "policy:%") or like(c.issued_by, "pm:%"),
        select: %{
          by: c.issued_by,
          command: c.type,
          type: e.type,
          timer: fragment("CASE WHEN ? = ? THEN ?->>'timer' END", e.type, ^elapsed, e.payload),
          id: c.id
        }
      )
      |> bounded(opts)

    from(r in subquery(reactions),
      group_by: [r.by, r.command, r.type, r.timer],
      select: {r.by, r.command, r.type, r.timer, count(r.id)}
    )
    |> repo().all()
    |> Map.new(fn {by, command, type, timer, taken} -> {{by, command, type, timer}, taken} end)
  end

  # A policy's commands, accepted or rejected, caused by a row its inbox took:
  # the cause a received event leaves, since the event is in no log here. Bounded by when the
  # row was taken, as a stored event's step is by when the event occurred. By the inboxes' keys,
  # the leading column of the inbox's key, and not at all for a contract with no inbox.
  defp received(model, steps, opts) do
    case for(%{inbox: inbox} <- steps, uniq: true, do: inbox) do
      [] ->
        %{}

      inboxes ->
        from(c in CommandRecord,
          join: i in InboxRecord,
          on: i.id == c.causation_event_id,
          where: i.consumer in ^inboxes,
          where: c.contract == ^model.id,
          where: c.outcome in ["accepted", "rejected"],
          where: like(c.issued_by, "policy:%"),
          group_by: [c.issued_by, c.type, i.consumer],
          select: {c.issued_by, c.type, i.consumer, count(c.id)}
        )
        |> received_between(opts)
        |> repo().all()
        |> Map.new(fn {by, command, inbox, taken} ->
          {{by, command, {:inbox, inbox}, nil}, taken}
        end)
    end
  end

  defp received_between(query, opts) do
    query
    |> then(fn q ->
      if at = opts[:since], do: where(q, [_c, i], i.received_at >= ^at), else: q
    end)
    |> then(fn q ->
      if at = opts[:until], do: where(q, [_c, i], i.received_at <= ^at), else: q
    end)
  end

  # --- phases -------------------------------------------------------------------------

  # The steps a process manager takes both as a run starts and during it — one event
  # in its `starts_on` and its `on`, the same command issued by both — each with its
  # runs and waiting events by phase: `%{{manager, event, command} => %{runs: %{phase
  # => runs}, lag: %{phase => events}}}`. The phase of an event is the one the manager's
  # own rule gives it over every event it takes before it, whatever the period, since a
  # run may have started before the period does.
  defp phases(model, opts) do
    for pm <- model.process_managers,
        shared = shared(pm),
        shared != [],
        entry <- phases_of(model, pm, shared, opts),
        into: %{},
        do: entry
  end

  defp shared(pm) do
    for start <- pm.starts_on,
        during <- pm.on,
        start.event == during.event,
        command <- start.issues,
        command in during.issues,
        uniq: true,
        do: {start.event, command}
  end

  defp phases_of(model, pm, shared, opts) do
    names =
      for name <- Enum.map(pm.starts_on ++ pm.on, & &1.event) ++ pm.ends_on,
          type = type_of(model, name),
          type != nil,
          into: %{},
          do: {type, name}

    rows =
      from(e in Event, where: e.type in ^Map.keys(names), order_by: e.position)
      |> repo().all()

    arrivals = ProcessManager.arrivals(pm, decoded(rows, names))
    key = key(model, :process_manager, pm.name)
    position = subscribed_at(key, pm.delivery)

    for {event, command} <- shared, type = type_of(model, event), type != nil do
      runs =
        from(c in CommandRecord,
          join: e in Event,
          as: :event,
          on: e.id == c.causation_event_id,
          where: c.contract == ^inspect(model.module) and c.issued_by == ^"pm:#{pm.name}",
          where: c.outcome in ["accepted", "rejected"],
          where: c.type == ^Atom.to_string(command) and e.type == ^type,
          select: {e.id, c.instance_id}
        )
        |> bounded(opts)
        |> repo().all()
        |> Enum.group_by(&Map.get(arrivals, elem(&1, 0)), &elem(&1, 1))
        |> Map.new(fn {phase, instances} -> {phase, instances |> Enum.uniq() |> length()} end)

      lag =
        if position,
          do:
            for(
              %{type: ^type, position: at, id: id} <- rows,
              at > position,
              phase = Map.get(arrivals, id),
              phase != nil,
              reduce: %{},
              do: (acc -> Map.update(acc, phase, 1, &(&1 + 1)))
            ),
          else: %{}

      {{pm.name, event, Atom.to_string(command)}, %{runs: runs, lag: lag}}
    end
  end

  # The rows decoded as the manager's subscription decodes them, each contract's with
  # its own declarations, back in the log's order — up to the first row that does not
  # decode, where the subscription stops too: what comes after it has no phase yet, so
  # a row the runtime cannot read never makes the overlay fail where the report says
  # the subscription is failing.
  defp decoded(rows, names) do
    decoded =
      rows
      |> Enum.group_by(& &1.contract)
      |> Enum.flat_map(fn {contract, rows} -> decode_each(contract, rows) end)
      |> Enum.sort_by(fn {row, _event} -> row.position end)

    decoded
    |> Enum.take_while(fn {_row, event} -> event != :undecodable end)
    |> Enum.map(fn {row, event} -> {row.id, Map.fetch!(names, row.type), event} end)
  end

  defp decode_each(contract, rows) do
    model = Model.fetch(Module.safe_concat([contract]))
    values = Codec.values(model.domain)

    try do
      Enum.zip(rows, Consumer.decode_all!(model, values, rows))
    rescue
      _one_does_not ->
        for row <- rows do
          try do
            {row, hd(Consumer.decode_all!(model, values, [row]))}
          rescue
            _it_does_not -> {row, :undecodable}
          end
        end
    end
  end

  # Where an ordered manager's subscription stands, as `lag/1` reads it; nil for one
  # inside the dispatch transaction, or not deployed, for which nothing waits.
  defp subscribed_at(_key, :in_transaction), do: nil

  defp subscribed_at(key, _delivery) do
    case repo().get_by(SubscriptionRecord, name: key) do
      %SubscriptionRecord{position: position} -> position
      nil -> nil
    end
  end

  # --- waiting ------------------------------------------------------------------------

  # Events of each type an ordered consumer takes, past the position its row is at.
  # A consumer with no row has not been deployed, and nothing waits for it.
  defp lag(steps) do
    ordered =
      for %{mode: :async, key: key, from_type: type} = step <- steps,
          type != nil,
          do: {key, type, timer_name(step)}

    rows =
      Map.new(
        repo().all(
          from(s in SubscriptionRecord, where: s.name in ^Enum.map(ordered, &elem(&1, 0)))
        ),
        &{&1.name, &1}
      )

    for {key, type, timer} = entry <- Enum.uniq(ordered),
        row = Map.get(rows, key),
        row != nil,
        into: %{} do
      waiting =
        from(e in Event,
          where: e.type == ^type and e.position > ^row.position,
          select: count(e.position)
        )
        |> fired(key, timer)
        |> repo().one()

      {entry, waiting}
    end
  end

  # Every timer of every process manager fires as one type, so a timer's step waits
  # only on the firings of that timer of that process manager.
  defp fired(query, _key, nil), do: query

  defp fired(query, key, timer) do
    where(
      query,
      [e],
      fragment("?->>'process_manager'", e.payload) == ^key and
        fragment("?->>'timer'", e.payload) == ^timer
    )
  end

  # Oban's jobs are where its `prefix:` puts them, which need not be on the
  # connection's `search_path` that finds the engine's own tables. A node that runs
  # no Oban still reports, as before: its jobs are looked for on the path.
  defp oban_jobs do
    prefix = if Oban.whereis(Oban), do: Oban.config().prefix
    from(Oban.Job, prefix: ^prefix)
  end

  # Only this contract's consumers' jobs: a report per contract must not scan every
  # job of the application.
  defp scheduled_timers(keys) do
    from(j in oban_jobs(),
      where: j.worker == "EhOsContract.TimerJob" and j.state in @waiting,
      where: fragment("?->>'process_manager'", j.args) in ^keys,
      group_by: [fragment("?->>'process_manager'", j.args), fragment("?->>'timer'", j.args)],
      select:
        {fragment("?->>'process_manager'", j.args), fragment("?->>'timer'", j.args), count(j.id)}
    )
    |> repo().all()
    |> Map.new(fn {key, timer, n} -> {{key, timer}, n} end)
  end

  # Effect jobs by effect and the type of the event each was enqueued for: waiting,
  # and discarded by Oban after its attempts.
  defp effect_jobs(keys) do
    rows =
      from(j in oban_jobs(),
        join: e in Event,
        on: fragment("(?->>'event_id')::uuid", j.args) == e.id,
        where: j.worker == "EhOsContract.EffectJob",
        where: fragment("?->>'effect'", j.args) in ^keys,
        where: j.state in ^["discarded" | @waiting],
        group_by: [fragment("?->>'effect'", j.args), e.type, j.state],
        select: {fragment("?->>'effect'", j.args), e.type, j.state, count(j.id)}
      )
      |> repo().all()

    {counts(rows, &(&1 in @waiting)), counts(rows, &(&1 == "discarded"))}
  end

  defp counts(rows, state?) do
    for {key, type, state, n} <- rows, state?.(state), reduce: %{} do
      acc -> Map.update(acc, {key, type}, n, &(&1 + n))
    end
  end

  # --- failing ------------------------------------------------------------------------

  defp failed_commands(model, opts) do
    from(c in CommandRecord,
      where: c.contract == ^model.id and c.outcome == "failed",
      select: %{
        type: c.type,
        failed_in: c.failed_in,
        issued_by: c.issued_by,
        at: c.recorded_at
      }
    )
    |> bounded_rows(opts)
    |> repo().all()
  end

  # A failure inside a consumer's stage is that consumer's step, which is how dispatch
  # names the stage (`EhOsContract.Consumer.label/1`); anywhere else — the decision,
  # the fold, a read model — it is every step the command emits.
  # A delivery the inbox's policy fails on is rolled back with its row, so a failed command named
  # after the policy is the policy's on the log, not this step's.
  defp failed_in_step(%{inbox: _inbox}, _failed), do: 0

  defp failed_in_step(%{via: %{kind: kind, name: name}}, failed) do
    label = "#{kind}:#{name}"
    Enum.count(failed, &(&1.failed_in == label))
  end

  defp failed_in_step(%{via: nil, command_type: command}, failed) do
    Enum.count(failed, &(&1.type == command and not consumer_stage?(&1.failed_in)))
  end

  defp consumer_stage?(failed_in),
    do: String.starts_with?(failed_in || "", ["policy:", "process_manager:", "effect:"])

  # By the consumers' keys, which the steps know, rather than by a pattern on the
  # contract's name: `_` in a module name is a wildcard to `LIKE`.
  defp stopped_subscriptions(steps) do
    keys = for %{key: key} <- steps, uniq: true, do: key

    from(s in SubscriptionRecord, where: s.status == "failing" and s.name in ^keys)
    |> repo().all()
    |> Map.new(&{&1.name, %{stopped_at: &1.failed_position, failure: &1.failure}})
  end

  # --- bounds --------------------------------------------------------------------------

  defp bounded(query, opts) do
    query
    |> then(fn q ->
      if at = opts[:since], do: where(q, [event: e], e.occurred_at >= ^at), else: q
    end)
    |> then(fn q ->
      if at = opts[:until], do: where(q, [event: e], e.occurred_at <= ^at), else: q
    end)
  end

  defp bounded_rows(query, opts) do
    query
    |> then(fn q -> if at = opts[:since], do: where(q, [c], c.recorded_at >= ^at), else: q end)
    |> then(fn q -> if at = opts[:until], do: where(q, [c], c.recorded_at <= ^at), else: q end)
  end

  defp repo, do: EhOsContract.Config.fetch!(:repo)
end
