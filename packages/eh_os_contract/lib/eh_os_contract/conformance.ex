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
  `promises` (v2 §13, plan E7c). `as_data/2` names the shape
  `eh_os_contract.conformance.v2`.

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
  def report(contract, opts \\ []), do: contract |> Model.fetch() |> report_v2(opts)

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

  @spec report_v2(map(), keyword()) :: map()
  defp report_v2(model, opts) do
    deployment = Deployment.report(model.module, opts)

    %{
      contract: model.module,
      engine: EhOsContract.version(),
      period: %{since: Keyword.get(opts, :since), until: Keyword.get(opts, :until)},
      deployment: deployment,
      # The code's half of the deployment, beside the agreement's: a v2 contract's
      # wiring is its steps and the modules that implement them.
      wiring: %{version: deployment.deployed.wiring_version, since: deployment.deployed.since},
      processes: List.wrap(model.process && process_v2(model, opts)),
      scenarios: EhOsContract.Coverage.of(model, opts),
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

  # The process `deadline`, measured. `nil` — not a map of zeroes — when the process
  # declares none or has not confirmed the one it declares. A number the client never
  # agreed to, printed next to numbers they did, reads as measured.
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
