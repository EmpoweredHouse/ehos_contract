defmodule EhOsContract.Conformance do
  @moduledoc """
  The answers to the screen's four questions, computed from the contract and the log.

  This module is where they converge, so that the report did not appear as a
  fourth mix task beside three others.

  ## Where lying is easy

  The report answers per **run**, because that is the only answer that means
  anything once there are many clients. And it has to avoid lying in the three
  situations where lying is easy:

  **Zero runs is no basis for a verdict, not three untraversed paths.** A process
  that never started has every step untraversed — and listing them as findings
  turns "no data" into "we have three problems". This is the same rule promise
  evaluation rests on: with no `from` there is nothing to judge. So with zero runs
  the list of untraversed steps is **empty**.

  **Work waiting in a queue is "not yet", not "never".** A step whose event will be
  produced by queued work is listed as in flight rather than as untraversed, and so
  is every step behind it. Without that the report would lie on every ordinary
  delay.

  **A path being attempted and failing is not a dead path.** "Declared, never
  observed" reads as a dead contract or an untested path, and for code that runs
  and crashes on every run both readings are wrong — the path is wired, exercised
  and broken, which is the opposite finding and goes to a different person. So a
  failing step is listed apart, with its source. The report must not turn *no
  answer* into *the answer is no*.

  ## The shape

  A path is a step of `EhOsContract.Paths`, so the command is a node, and what
  waits and what fails is split by source; the assertions are the process's
  `promises` (v2 §13, plan E7c). An aggregate that declares its lifecycle adds the
  first two questions for its transitions, under `lifecycles` (plan LC3). `as_data/2`
  names the shape `eh_os_contract.conformance.v2`.

  ## The boundary

  The report talks about **paths**, not about companies. If 47 of 50 runs did not
  take a path, the finding is the path and the number; which runs those were is a
  question about the state of the business and belongs to the client application.
  """

  import Ecto.Query

  alias EhOsContract.{Deployment, Model, Trace}

  @doc """
  All four of the screen's questions for one contract over a period, as data.

  This module produces the answers; it does not render them. The wording of a
  client-facing report belongs to the client application, because the engine
  cannot know the language its readers speak — every business string in here
  comes from the contract's own `label`, which is the one place written in the
  client's language.

  ## `unverified` declarations are omitted, not marked

  A process declaration or a promise the process owner has not confirmed **does
  not appear**.
  `mix eh_os_contract.check` warns about it on every run, which is right for a developer
  check, but an evidence report is a different artifact with a different reader:
  a number the client never agreed to, printed next to numbers they did, reads as
  measured. A false metric is worse than a missing one when it is the metric the
  product sells. `EhOsContract.Trace.evaluate/3` still evaluates an unconfirmed
  promise; the report is the only thing that omits it.
  """
  @spec report(module(), keyword()) :: map()
  def report(contract, opts \\ []), do: contract |> Model.fetch() |> from_model(opts)

  @doc """
  The same report, projected onto values that survive JSON.

  Separate from `report/2` rather than replacing it: everything in this package
  reads the Elixir shape, and a transport is the only caller that needs the other
  one. See `EhOsContract.Conformance.Wire` for what each mapping is and why.
  """
  @spec as_data(module(), keyword()) :: map()
  def as_data(contract, opts \\ []) do
    %{
      # A name for the shape, so a consumer comparing two responses can tell a
      # changed report from a changed projection. The engine version is already
      # inside the report itself and is deliberately not repeated here.
      "schema" => "eh_os_contract.conformance.v2",
      "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "report" => contract |> report(opts) |> EhOsContract.Conformance.Wire.encode()
    }
  end

  # --- a v2 contract (v2 §13, plan E7c) ---------------------------------------------------
  #
  # The same four questions. A path is a step of `EhOsContract.Paths` — from, via, to,
  # each `%{kind, name, label}` — with its runs and each source of waiting and failing
  # apart; the assertions are the process's promises, judged by `EhOsContract.Trace`;
  # the deployed version is `EhOsContract.Deployment`'s. What is left out: a
  # declaration or a promise the owner has not confirmed, and every step when no run
  # happened.

  @spec from_model(map(), keyword()) :: map()
  defp from_model(model, opts) do
    deployment = Deployment.report(model.module, opts)

    %{
      contract: model.module,
      engine: EhOsContract.version(),
      period: %{since: Keyword.get(opts, :since), until: Keyword.get(opts, :until)},
      deployment: deployment,
      # The code's half of the deployment, beside the agreement's: a v2 contract's
      # wiring is its steps and the modules that implement them.
      wiring: %{version: deployment.deployed.wiring_version, since: deployment.deployed.since},
      processes: List.wrap(model.process && process_report(model, opts)),
      lifecycles: lifecycles(model, opts),
      scenarios: EhOsContract.Coverage.of(model, opts),
      drift: drift(model, opts)
    }
  end

  @spec process_report(map(), keyword()) :: map()
  defp process_report(model, opts) do
    process = model.process
    steps = EhOsContract.Paths.observe(model, opts)
    runs = EhOsContract.Paths.runs_of(model, Atom.to_string(process.name), opts)

    in_flight = Enum.filter(steps, &waiting?/1)
    failing = Enum.filter(steps, &failing?/1)

    pending = downstream_of(in_flight, steps)

    untraversed =
      if runs > 0,
        do:
          Enum.filter(
            steps,
            &(&1.runs == 0 and not waiting?(&1) and not failing?(&1) and
                not MapSet.member?(pending, &1.from))
          ),
        else: []

    %{
      process: process.name,
      label: process.label,
      accountable: actor_label(model, process.accountable),
      runs: runs,
      declarations:
        for key <- [:cadence, :deadline],
            %{unverified: false} = value <- [Map.get(process, key)] do
          %{key: key, value: {value.amount, value.unit}}
        end,
      untraversed: untraversed,
      in_flight: in_flight,
      failing: failing,
      duration: duration(model, opts),
      promises: promises(model, opts)
    }
  end

  defp waiting?(step), do: Enum.any?(Map.values(step.in_flight), &(&1 > 0))

  # What a waiting step leads to, and what that leads to in turn: a step starting there
  # has not been taken *yet*, since what it starts from is still on its way. Without
  # this a chain of steps behind one queue reads as "never" everywhere but its head.
  @spec downstream_of([map()], [map()]) :: MapSet.t()
  defp downstream_of(waiting, steps) do
    reached = for %{to: %{} = to} <- waiting, into: MapSet.new(), do: to
    close(reached, steps)
  end

  defp close(reached, steps) do
    more =
      for %{from: from, to: %{} = to} <- steps,
          MapSet.member?(reached, from),
          not MapSet.member?(reached, to),
          into: MapSet.new(),
          do: to

    if MapSet.size(more) == 0, do: reached, else: close(MapSet.union(reached, more), steps)
  end

  defp failing?(%{failing: f}), do: f.commands > 0 or f.effects > 0 or f.subscription != nil

  # The role, as the domain names the actor the process is addressed to.
  defp actor_label(_model, nil), do: nil

  defp actor_label(model, actor) do
    case Enum.find(Model.fetch(model.domain).actors, &(&1.name == actor)) do
      %{label: label} -> label
      nil -> Atom.to_string(actor)
    end
  end

  # The process `deadline`, measured. `nil` — not a map of zeroes — when the process
  # declares none or has not confirmed the one it declares. A number the client never
  # agreed to, printed next to numbers they did, reads as measured.
  defp duration(%{process: %{deadline: %{unverified: false} = deadline}} = model, opts) do
    model.module
    |> EhOsContract.Run.evaluate(model.process.name, opts)
    |> EhOsContract.Run.summary()
    |> Map.put(:deadline, {deadline.amount, deadline.unit})
  end

  defp duration(_model, _opts), do: nil

  defp promises(model, opts) do
    label = fn name ->
      case name && Model.declaring(model, name) do
        {_contract, event} -> event.label
        _none -> name && Atom.to_string(name)
      end
    end

    boundaries = Deployment.declaration_boundaries(model.module)

    for promise <- model.process.promises, not promise.unverified do
      verdicts = Trace.evaluate(model.module, promise.name, opts)
      boundary = Map.get(boundaries, "promise:#{promise.name}")
      {current, earlier} = split_by_declaration(verdicts, boundary)

      %{
        promise: promise.name,
        from_label: label.(promise.from),
        eventually_label: label.(promise.eventually),
        or_else_label: label.(promise.or_else),
        within: promise.within && {promise.within.amount, promise.within.unit},
        declaration_changed_at: boundary,
        under_earlier_declaration: length(earlier)
      }
      |> Map.merge(Trace.summary(current))
    end
  end

  # v2 refuses an undeclared emit at run time, so what is left of drift is what did
  # not come through dispatch under today's declarations: an event of the deployed
  # version that no command it declares emits — written around dispatch, when it
  # names no command at all. History under an older version is not drift.
  @spec drift(map(), keyword()) :: [map()]
  defp drift(model, opts) do
    declared =
      MapSet.new(
        for(c <- model.commands, e <- c.emits, do: {Atom.to_string(c.name), e}) ++
          for(%{recorded_by: [_ | _]} = e <- model.events, do: {"record:#{e.name}", e.name})
      )

    names = Map.new(model.events, &{&1.type, &1})
    commands = Map.new(model.commands, &{Atom.to_string(&1.name), &1})

    from(e in EhOsContract.Event,
      left_join: c in EhOsContract.CommandRecord,
      on: c.id == e.command_id,
      where: e.contract == ^inspect(model.module) and e.contract_version == ^model.version,
      group_by: [c.type, e.type],
      select: {c.type, e.type, count(e.id)}
    )
    |> drift_bounds(opts)
    |> repo().all()
    |> Enum.flat_map(fn {command, type, count} ->
      event = Map.get(names, type)

      if event == nil or MapSet.member?(declared, {command, event.name}) do
        []
      else
        from =
          case Map.get(commands, command) do
            nil -> nil
            c -> %{kind: :command, name: c.name, label: c.label}
          end

        [%{from: from, to: %{kind: :event, name: event.name, label: event.label}, count: count}]
      end
    end)
  end

  defp drift_bounds(query, opts) do
    query
    |> then(fn q -> if at = opts[:since], do: where(q, [e], e.occurred_at >= ^at), else: q end)
    |> then(fn q -> if at = opts[:until], do: where(q, [e], e.occurred_at <= ^at), else: q end)
  end

  defp repo, do: Application.fetch_env!(:eh_os_contract, :repo)

  # --- an aggregate's lifecycle (plan LC3, #99) -------------------------------------------
  #
  # The first two questions again, for an aggregate that declares its lifecycle: which
  # declared transitions no aggregate took, and which moves the graph does not allow
  # happened anyway. A process's steps go forward; an aggregate's statuses go round in
  # loops, so a path here is a transition, and what was not declared is what the status
  # could not follow. The status is walked over each aggregate's whole stream, by the
  # same graph dispatch holds it to, and only the events of the period are counted.
  # A stream is this contract's rows, as `drift` reads them: one a renamed module
  # wrote under its old name starts again from no status.
  #
  # Not lying here is the same as for a process. With no aggregate in the period
  # nothing is untraversed. And an aggregate that has not ended can still take every
  # transition it can reach from where it stands, so those are "not yet", listed
  # apart, never "never" — a visit still booked will be admitted or cancelled.

  @spec lifecycles(map(), keyword()) :: [map()]
  defp lifecycles(model, opts) do
    for %{lifecycle: lifecycle} = unit <- model.units do
      events = for e <- model.events, e.unit == unit.name, do: e
      names = Map.new(events, &{&1.type, &1.name})

      %{aggregates: aggregates, standing: standing, taken: taken, undeclared: undeclared} =
        tally(model, lifecycle, names, opts)

      reachable = reachable(lifecycle, standing)

      status = &status_ref(lifecycle, &1)
      event = &event_ref(events, &1)

      declared =
        for(i <- lifecycle.initial, do: {nil, i.on, i.status}) ++
          for t <- lifecycle.transitions, do: {t.from, t.event, t.to}

      transitions =
        for {from, on, to} = key <- declared do
          %{
            from: status.(from),
            event: event.(on),
            to: status.(to),
            count: Map.get(taken, key, 0)
          }
        end

      %{
        unit: unit.name,
        label: unit.label,
        aggregates: aggregates,
        transitions: transitions,
        untraversed:
          if(aggregates > 0,
            do: Enum.filter(transitions, &(&1.count == 0 and not pending?(&1, reachable))),
            else: []
          ),
        pending: Enum.filter(transitions, &(&1.count == 0 and pending?(&1, reachable))),
        undeclared:
          for {{from, on}, count} <-
                Enum.sort_by(undeclared, fn {{from, on}, count} -> {-count, from, on} end) do
            %{from: status.(from), event: event.(on), count: count}
          end
      }
    end
  end

  # Every status an aggregate standing in `standing` can still get to.
  defp reachable(lifecycle, standing) do
    edges = for t <- lifecycle.transitions, do: {t.from, t.to}
    grow(standing, edges)
  end

  defp grow(seen, edges) do
    more = for {from, to} <- edges, from in seen, to not in seen, into: MapSet.new(), do: to
    if MapSet.size(more) == 0, do: seen, else: grow(MapSet.union(seen, more), edges)
  end

  # An initial transition is never pending: an aggregate that will start has no
  # stream yet, and the period cannot be waiting for one.
  defp pending?(%{from: nil}, _reachable), do: false
  defp pending?(%{from: %{name: from}}, reachable), do: MapSet.member?(reachable, from)

  # The aggregates' streams, walked one at a time as the rows arrive: only those with
  # an event of these types in the period, each read whole, since the status at the
  # period's start is what its earlier events left. Rows without a stream belong to no
  # aggregate. Memory is the longest stream, never the log.
  defp tally(_model, lifecycle, names, _opts) when map_size(names) == 0,
    do: EhOsContract.Lifecycle.tally(lifecycle, [])

  defp tally(model, lifecycle, names, opts) do
    since = opts[:since]
    until = opts[:until]
    types = Map.keys(names)
    contract = inspect(model.module)

    of_these =
      from(e in EhOsContract.Event,
        where: e.contract == ^contract and e.type in ^types and not is_nil(e.stream_id)
      )

    in_period =
      of_these
      |> drift_bounds(opts)
      |> select([e], e.stream_id)

    query =
      from(e in of_these,
        where: e.stream_id in subquery(in_period),
        order_by: [e.stream_id, e.stream_version],
        select: {e.stream_id, e.type, e.occurred_at}
      )

    counted? = fn at ->
      (since == nil or DateTime.compare(at, since) != :lt) and
        (until == nil or DateTime.compare(at, until) != :gt)
    end

    {:ok, tally} =
      repo().transaction(fn ->
        query
        |> repo().stream(max_rows: 5_000)
        |> Stream.chunk_by(&elem(&1, 0))
        |> Stream.map(fn rows ->
          for {_stream, type, at} <- rows, do: {Map.get(names, type), counted?.(at)}
        end)
        |> then(&EhOsContract.Lifecycle.tally(lifecycle, &1))
      end)

    tally
  end

  # `nil` is where an aggregate stands before its first event: the start.
  defp status_ref(_lifecycle, nil), do: nil

  defp status_ref(lifecycle, name) do
    label = Enum.find_value(lifecycle.statuses, &(&1.name == name && &1.label))
    %{kind: :status, name: name, label: label || Atom.to_string(name)}
  end

  defp event_ref(events, name) do
    label = Enum.find_value(events, &(&1.name == name && &1.label))
    %{kind: :event, name: name, label: label || Atom.to_string(name)}
  end

  # Runs that began before this assertion was last changed were judged under a
  # promise that is no longer the one declared, so they do not belong in the same
  # counts. `EhOsContract.Trace` is not involved: every verdict already carries `from_at`,
  # which is the moment the promise attached to that run, and the question of which
  # promise was in force is the report's, not the evaluator's.
  #
  # The boundary is the last change full stop, not a change inside the reported
  # period. A report for July, run in September, on an assertion changed in August
  # is the case a period-bounded rule would miss — and it is the worse one, because
  # nothing in the output would hint that the rule had moved.
  #
  # Two buckets, not one per version: an assertion changed three times inside the
  # period puts two superseded rules in the same earlier count. That is a smaller
  # untruth than today's, which folds them into `satisfied`, and the report prints
  # the boundary date so a reader can narrow `--since` themselves.
  @spec split_by_declaration([map()], DateTime.t() | nil) :: {[map()], [map()]}
  defp split_by_declaration(verdicts, nil), do: {verdicts, []}

  defp split_by_declaration(verdicts, at) do
    # `!= :lt`, not `== :gt`: a run whose `from` lands in the same microsecond as
    # the deployment is judged under the new rule, because the new rule was in
    # force from that moment. Arbitrary at the boundary, but decided rather than
    # accidental.
    Enum.split_with(verdicts, &(DateTime.compare(&1.from_at, at) != :lt))
  end
end
