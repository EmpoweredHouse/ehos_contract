defmodule EhOsContract.Conformance do
  @moduledoc """
  The answers to the screen's four questions, computed from the contract and the log.

  This module is where they converge, so that the report did not appear as a
  fourth mix task beside three others.

  ## Why this is not simply `state: :dead` from the overlay

  The overlay answers per **edge** and per **event type**: "this edge has zero
  traversals". The report has to answer per **run**, because that is the only
  answer that means anything once there are many clients. And it has to avoid
  lying in the two situations where lying is easy:

  **Zero runs is no basis for a verdict, not three untraversed paths.** A process
  that never started has every edge untraversed — and listing them as findings
  turns "no data" into "we have three problems". This is the same rule assertion
  evaluation rests on: with no `from` there is nothing to judge. So with zero runs
  the report says `basis: :no_runs` and an **empty** list.

  **A job waiting in the queue is "not yet", not "never".** A path whose event
  will be produced by a queued job is listed separately rather than as
  untraversed. Without that the report would lie on every ordinary delay — and
  that is the lesson the overlay learned as its fourth state.

  **A path being attempted and failing is not a dead path.** "Declared, never
  observed" reads as a dead contract or an untested path, and for a handler that
  runs and crashes on every run both readings are wrong — the path is wired,
  exercised and broken, which is the opposite finding and goes to a different
  person. So an untraversed path carries how many runs its handler failed on
  (`EhOsContract.HandlerFailure`). This is the third variant of one mistake: the report must
  not turn *no answer* into *the answer is no*.

  ## A v2 contract

  **The same four questions, on the new log** (v2 §13, plan E7c). A path is a step
  of `EhOsContract.Paths`, so the command is a node, and what waits and what fails
  is split by source; the assertions are the process's `promises`. The report names
  its shape: `as_data/2` says `eh_os_contract.conformance.v2` for a v2 contract, and
  a v1 contract's stays `v1`.

  ## The boundary

  The report talks about **paths**, not about companies. If 47 of 50 runs did not
  take a path, the finding is the path and the number; which runs those were is a
  question about the state of the business and belongs to the client application.
  """

  import Ecto.Query

  alias EhOsContract.{Deployment, Graph, HandlerFailure, Model, Trace}

  @doc """
  All four of the screen's questions for one contract over a period, as data.

  This module produces the answers; it does not render them. The wording of a
  client-facing report belongs to the client application, because the engine
  cannot know the language its readers speak — every business string in here
  comes from the contract's own `label`, which is the one place written in the
  client's language.

  ## `unverified` declarations are omitted, not marked

  A process declaration the process owner has not confirmed **does not appear**.
  `mix eh_os_contract.check` warns about it on every run, which is right for a developer
  check, but an evidence report is a different artifact with a different reader:
  a number the client never agreed to, printed next to numbers they did, reads as
  measured. A false metric is worse than a missing one when it is the metric the
  product sells.

  **Since 21 August 2026, `unverified` also reaches a `trace` by name** — the
  sharpest assertion this engine can make is exactly the one most likely to be a
  guess, and until this date there was no way to write it down without either
  asserting it as fact or not writing it at all. `EhOsContract.Trace.evaluate/3` still
  evaluates it; `assertions/4` below is the only thing that omits it, the same
  split `verified_declarations/1` already draws for `cadence`/`deadline`.
  """
  @spec report(module(), keyword()) :: map()
  def report(contract, opts \\ []) do
    case Model.fetch(contract) do
      %{units: _} = model -> report_v2(model, opts)
      _v1 -> report_v1(contract, opts)
    end
  end

  @spec report_v1(module(), keyword()) :: map()
  defp report_v1(contract, opts) do
    paths = untraversed_paths(opts)
    nodes = Graph.static().nodes
    labels = Map.new(nodes, &{to_string(&1.event), &1.label})
    declared_by = Map.new(nodes, &{to_string(&1.event), &1.contract})
    # Once for the report, not once per assertion: it is a query.
    boundaries = Deployment.declaration_boundaries(contract)

    %{
      contract: contract,
      # In the data, not only in the rendered text: the report crosses a boundary
      # as JSON too, and an auditor reading it there needs the same fact.
      engine: EhOsContract.version(),
      period: %{since: Keyword.get(opts, :since), until: Keyword.get(opts, :until)},
      deployment: Deployment.report(contract, opts),
      processes:
        for process <- Model.processes(contract) do
          answers = Enum.find(paths, &(&1.process == process.name))

          %{
            process: process.name,
            label: process.label,
            # Who the finding is addressed to. A report saying "this rule was broken
            # in 1 of 40 runs" and naming nobody is a report with no recipient, which
            # is what `D-18` is about.
            accountable: process.accountable,
            runs: (answers && answers.instances) || 0,
            declarations: verified_declarations(process),
            untraversed: label_edges(answers && answers.untraversed, labels),
            in_flight: label_edges(answers && answers.in_flight, labels),
            failing: label_edges(answers && answers.failing, labels),
            duration: duration(contract, process, opts),
            assertions: assertions(contract, process, labels, boundaries, opts)
          }
        end,
      drift: drift(contract, labels, declared_by, opts)
    }
  end

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
      # inside the report itself and is deliberately not repeated here. A v2
      # contract's report has other steps and names its promises, so it is another
      # shape; a v1 contract's stays `v1`, byte for byte, until v1 is cut.
      "schema" => schema(contract),
      "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "report" => contract |> report(opts) |> EhOsContract.Conformance.Wire.encode()
    }
  end

  @spec schema(module()) :: String.t()
  defp schema(contract) do
    case Model.fetch(contract) do
      %{units: _} -> "eh_os_contract.conformance.v2"
      _v1 -> "eh_os_contract.conformance.v1"
    end
  end

  # --- a v2 contract (v2 §13, plan E7c) ---------------------------------------------------
  #
  # The same four questions. A path is a step of `EhOsContract.Paths` — from, via, to,
  # each `%{kind, name, label}` — with its runs and each source of waiting and failing
  # apart; the assertions are the process's promises, judged by `EhOsContract.Trace`;
  # the deployed version is `EhOsContract.Deployment`'s, as for v1. What is left out
  # for the same reasons as in v1: a declaration or a promise the owner has not
  # confirmed, and every step when no run happened.

  @spec report_v2(map(), keyword()) :: map()
  defp report_v2(model, opts) do
    %{
      contract: model.module,
      engine: EhOsContract.version(),
      period: %{since: Keyword.get(opts, :since), until: Keyword.get(opts, :until)},
      deployment: Deployment.report(model.module, opts),
      processes: List.wrap(model.process && process_v2(model, opts)),
      drift: drift_v2(model, opts)
    }
  end

  @spec process_v2(map(), keyword()) :: map()
  defp process_v2(model, opts) do
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
      duration: duration_v2(model, opts),
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

  defp duration_v2(%{process: %{deadline: %{unverified: false} = deadline}} = model, opts) do
    model.module
    |> EhOsContract.Run.evaluate(model.process.name, opts)
    |> EhOsContract.Run.summary()
    |> Map.put(:deadline, {deadline.amount, deadline.unit})
  end

  defp duration_v2(_model, _opts), do: nil

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
  @spec drift_v2(map(), keyword()) :: [map()]
  defp drift_v2(model, opts) do
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

  @doc """
  Process declarations that may appear in an evidence report: those the process
  owner has confirmed.

  Public because it is the rule the acceptance criterion of stage 1.7 is about,
  and a rule that cannot be tested directly is a rule that quietly stops
  applying. `unverified` lists what is excluded.
  """
  @spec verified_declarations(map()) :: [%{key: atom(), value: term()}]
  def verified_declarations(process) do
    for key <- [:cadence, :deadline],
        key not in process.unverified,
        value = Map.get(process, key),
        not is_nil(value) do
      %{key: key, value: value}
    end
  end

  # **An assertion is reported as the sentence the process owner confirmed**, not
  # as its name. `trace` is the one declaration without a `label`, so a technical
  # atom is all a name could contribute — and a client-facing report that prints
  # `month_opens_or_is_blocked` fails the criterion of being readable without
  # explanation.
  #
  # Composing it from the event labels is not a workaround: those labels are the
  # words the client already agreed to, and the sentence they compose is the
  # assertion. Whether the process owner also wants to *name* assertions is a
  # question for the workshop, not for us — recorded in PLAN.md rather than
  # answered by adding a key.
  #
  # **`unverified` reaches a `trace` by name, the same way it already reaches
  # `cadence`/`deadline` by key.** Fixed 21 August 2026 — before this, a `trace`
  # nobody confirmed had no way to stay out of the report except not writing it at
  # all, which loses the assertion's own value as a `mix eh_os_contract.trace` observation.
  # `EhOsContract.Trace.evaluate/3` still runs and still counts here internally — omitted
  # is only whether this function hands its summary to the report the client
  # reads, the same distinction `verified_declarations/1` already draws.
  # The process `deadline`, measured. `nil` — not a map of zeroes — when the process
  # declares none or has not confirmed the one it declares: exactly the split
  # `verified_declarations/1` draws, for the same reason. A number the client never
  # agreed to, printed next to numbers they did, reads as measured.
  @spec duration(module(), map(), keyword()) :: map() | nil
  defp duration(contract, process, opts) do
    if process.deadline && :deadline not in process.unverified do
      contract
      |> EhOsContract.Run.evaluate(process.name, opts)
      |> EhOsContract.Run.summary()
      |> Map.put(:deadline, process.deadline)
    end
  end

  @spec assertions(module(), map(), map(), %{String.t() => DateTime.t()}, keyword()) :: [map()]
  defp assertions(contract, process, labels, boundaries, opts) do
    for trace <- Model.traces(contract),
        Model.process_of(contract, trace.from).name == process.name,
        trace.name not in process.unverified do
      verdicts = Trace.evaluate(contract, trace.name, opts)
      label = fn name -> name && Map.get(labels, to_string(name), to_string(name)) end
      boundary = Map.get(boundaries, "trace:#{trace.name}")
      {current, earlier} = split_by_declaration(verdicts, boundary)

      %{
        trace: trace.name,
        from_label: label.(trace.from),
        eventually_label: label.(trace.eventually),
        or_else_label: label.(trace.or_else),
        within: trace.within,
        declaration_changed_at: boundary,
        under_earlier_declaration: length(earlier)
      }
      |> Map.merge(Trace.summary(current))
    end
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

  # A drift edge has no contract of its own: its **target** is undeclared, which
  # is what makes it drift, so there is nothing there to attribute. Its
  # **source** is declared, and that is what attributes the finding — otherwise
  # every contract's report would list every other contract's drift.
  @spec drift(module(), map(), map(), keyword()) :: [map()]
  defp drift(contract, labels, declared_by, opts) do
    for edge <- Graph.overlay(opts),
        edge.state == :drift,
        Map.get(declared_by, to_string(edge.from)) == contract do
      %{
        from: to_string(edge.from),
        to: to_string(edge.to),
        from_label: labels[to_string(edge.from)],
        to_label: labels[to_string(edge.to)],
        count: edge.count
      }
    end
  end

  @spec label_edges([map()] | nil, map()) :: [map()]
  defp label_edges(nil, _labels), do: []

  defp label_edges(edges, labels) do
    for edge <- edges do
      %{
        from: edge.from,
        to: edge.to,
        from_label: labels[to_string(edge.from)],
        to_label: labels[to_string(edge.to)],
        async: edge.async,
        in_flight: edge.in_flight,
        failing: edge.failing
      }
    end
  end

  @doc """
  Paths declared in the contract that **no run has taken**, grouped by process.

  Also returns the denominator (`instances`) and, separately, the paths waiting in
  the queue, because without both of those the count of untraversed paths means
  nothing.
  """
  @spec untraversed_paths(keyword()) :: [map()]
  def untraversed_paths(opts \\ []) do
    failures = HandlerFailure.runs_by_handler(opts)

    edges =
      Graph.overlay(opts)
      # Only **declared** edges. Observed-but-undeclared is drift, which is a
      # different question on the screen, and mixing them into one list turns the
      # report into a bag.
      |> Enum.filter(& &1.handler)
      |> Enum.map(&Map.put(&1, :failing, Map.get(failures, inspect(&1.handler), 0)))
      |> Enum.group_by(& &1.process)

    # Iterating over **processes from the registry**, not over edges from the log.
    # The version that grouped by edges skipped a process with no handlers at all
    # — so the whole universality gate contract was **absent** from the report.
    # And absence reads as "there is nothing to discuss", which is the same
    # silence-pretending-to-be-health this product is meant to detect.
    for contract <- EhOsContract.Registry.contracts(), process <- Model.processes(contract) do
      report(contract, process, Map.get(edges, process.name, []))
    end
    |> Enum.sort_by(&to_string(&1.process))
  end

  # A process with no declared path at all. It may still have runs — and then that
  # is a finding in itself: events are flowing and nothing is wired up.
  @spec report(module(), map(), [map()]) :: map()
  defp report(contract, process, []) do
    %{
      process: process.name,
      contract: contract,
      paths: 0,
      instances: 0,
      basis: :no_paths,
      untraversed: [],
      in_flight: [],
      failing: []
    }
  end

  defp report(contract, process, edges) do
    runs = edges |> Enum.map(& &1.of_instances) |> Enum.max()
    unobserved = if runs > 0, do: Enum.filter(edges, &untraversed?/1), else: []

    %{
      process: process.name,
      contract: contract,
      # The denominator for the finding itself: "2 of 3 untraversed" means
      # something different from "2 of 40". Computed here rather than in the
      # renderer, because it is part of the answer.
      paths: length(edges),
      instances: runs,
      basis: if(runs > 0, do: :runs, else: :no_runs),
      # A path whose handler is failing is **not** in the untraversed list. It is a
      # different finding with a different reader: untraversed asks the process
      # owner whether the path is still agreed, failing tells a developer their code
      # is broken. Leaving it in both would put a bug in front of the client as a
      # question about their process.
      untraversed: Enum.reject(unobserved, &(&1.failing > 0)),
      in_flight: Enum.filter(edges, &(&1.in_flight > 0)),
      failing: Enum.filter(unobserved, &(&1.failing > 0))
    }
  end

  # Untraversed means: **zero runs** took it and nothing is waiting for it in the
  # queue. A count of runs rather than of occurrences — because that is the only
  # number that separates silence from low traffic once there are many clients.
  @spec untraversed?(map()) :: boolean()
  defp untraversed?(edge), do: edge.instances == 0 and edge.in_flight == 0
end
