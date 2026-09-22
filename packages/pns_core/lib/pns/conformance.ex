defmodule PNS.Conformance do
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
  (`PNS.HandlerFailure`). This is the third variant of one mistake: the report must
  not turn *no answer* into *the answer is no*.

  ## The boundary

  The report talks about **paths**, not about companies. If 47 of 50 runs did not
  take a path, the finding is the path and the number; which runs those were is a
  question about the state of the business and belongs to the client application.
  """

  alias PNS.{Deployment, Graph, HandlerFailure, Trace}

  @doc """
  All four of the screen's questions for one contract over a period, as data.

  This module produces the answers; it does not render them. The wording of a
  client-facing report belongs to the client application, because the engine
  cannot know the language its readers speak — every business string in here
  comes from the contract's own `label`, which is the one place written in the
  client's language.

  ## `unverified` declarations are omitted, not marked

  A process declaration the process owner has not confirmed **does not appear**.
  `mix pns.check` warns about it on every run, which is right for a developer
  check, but an evidence report is a different artifact with a different reader:
  a number the client never agreed to, printed next to numbers they did, reads as
  measured. A false metric is worse than a missing one when it is the metric the
  product sells.

  **Since 21 August 2026, `unverified` also reaches a `trace` by name** — the
  sharpest assertion this engine can make is exactly the one most likely to be a
  guess, and until this date there was no way to write it down without either
  asserting it as fact or not writing it at all. `PNS.Trace.evaluate/3` still
  evaluates it; `assertions/4` below is the only thing that omits it, the same
  split `verified_declarations/1` already draws for `cadence`/`deadline`.
  """
  @spec report(module(), keyword()) :: map()
  def report(contract, opts \\ []) do
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
      engine: PNS.version(),
      period: %{since: Keyword.get(opts, :since), until: Keyword.get(opts, :until)},
      deployment: Deployment.report(contract, opts),
      processes:
        for process <- contract.processes() do
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
  # all, which loses the assertion's own value as a `mix pns.trace` observation.
  # `PNS.Trace.evaluate/3` still runs and still counts here internally — omitted
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
      |> PNS.Run.evaluate(process.name, opts)
      |> PNS.Run.summary()
      |> Map.put(:deadline, process.deadline)
    end
  end

  @spec assertions(module(), map(), map(), %{String.t() => DateTime.t()}, keyword()) :: [map()]
  defp assertions(contract, process, labels, boundaries, opts) do
    for trace <- contract.traces(),
        contract.process_of(trace.from).name == process.name,
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
  # counts. `PNS.Trace` is not involved: every verdict already carries `from_at`,
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
    for contract <- PNS.Registry.contracts(), process <- contract.processes() do
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
