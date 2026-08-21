defmodule PNS.Trace do
  @moduledoc """
  Evaluation of `trace` assertions **per run**.

  This is the first moment anything at run time **reads** a `trace`. Until now an
  assertion was declared in the contract and checked only for whether its event
  names existed — that is, it was prose in Elixir syntax. The log knew what
  happened; nobody asked whether that agreed with the contract.

  An assertion reads like this:

      trace :month_opens_or_is_blocked do
        from :data_completeness_confirmed
        eventually :accounting_month_opened, within: {2, :day}
        or_else :discrepancy_notification_sent
      end

  *"After the data set is confirmed complete, within two days the month either
  opens or a divergence notification goes out."*

  ## Four verdicts

  | Verdict | Meaning |
  |---|---|
  | `:satisfied` | `eventually` **or** `or_else` occurred inside the window |
  | `:violated` | the window passed and neither occurred |
  | `:pending` | the window has not passed yet — nothing is known |
  | `:suspended` | the window passed, and a dependency this path needs was seen unavailable inside it |

  **`:satisfied` carries `via:`** — `:eventually` or `:or_else`. That is the whole
  subtlety of this assertion and the easiest thing to get wrong: blocking the
  month is a **correct ending**, just not the one we wanted. The verdict has to
  read "satisfied", and the report has to be able to say by which route — because
  a tool that shouts about every correctly blocked month gets switched off within
  a week.

  **`:suspended` only ever replaces `:violated`.** It never touches `:satisfied` — a run
  that ended correctly ended correctly, whatever was down at the time — and it never
  touches `:pending`, because there is still time. So it removes a finding from the report
  and adds nothing, which is why the recording behind it (`PNS.Dependency`) is deliberately
  reluctant: over-recording unavailability would quietly stop reporting real problems.

  **Which dependency counts is narrow: the ones declared by the events that did not
  arrive.** `from` already happened, so whatever it needed was working. What blocked the
  run is whatever `eventually` or `or_else` depends on. Taking the union of the whole
  contract's dependencies would suspend a run because something unrelated was down.

  **This union is `eventually`'s dependency `or` `or_else`'s, not their intersection —
  decided rather than assumed, 21 August 2026.** A narrower reading was on the table: a
  wanted route with no dependency at all can never be blocked by an outage, so suspend
  only when every still-possible route was. Rejected, because the promise a `trace`
  makes is the disjunction itself — "X or Y" — and here Y was impossible, which stands
  as a reason to withhold judgement on the run even when X depended on nothing.
  `test/trace_edges_test.exs` pins this.

  ## Three decisions with teeth

  **The window runs from the first occurrence of `from`, not from the last.** If
  it ran from the last, a process could outrun its own deadline forever by simply
  emitting `from` again — the assertion could never be violated. Where a check
  gets repeated, that is not a theoretical case.

  **`within` binds `or_else` as well.** "Within two days, X or Y" means both are
  meant to fit. The variant where `or_else` has no deadline makes the deadline
  useless: a process that ended correctly but three months later would be
  "satisfied". This one is the **process owner's decision**, not ours, and is the
  first thing to confirm about this assertion.

  **The assertion is conditional: a run with no `from` is not evaluated.** It is
  neither satisfied nor violated — there is nothing to judge. Counting it as a
  violation would raise an alarm for every case not yet started.

  ## Quantification: a promise made per item inside a run

  **Fixed 21 August 2026** — until then an assertion was evaluated once per run
  regardless of how many times the thing it promised about occurred inside it: the
  window opened on the first `from` and closed on the first hit after it, so one
  fulfilment satisfied every promise in the run, and the hit did not even have to
  concern the same item — nothing compared payloads. `test/trace_granularity_test.exs`
  pins that shape as history now, not as the requirement.

  `PNS.Check.assertions_finer_than_their_run/1` already had the signal: when the
  `from` event's `identity` is strictly finer than its process's `instance`, the run
  holds more than one of the thing the assertion is about. `evaluate/3` reads that
  same signal and switches modes:

  - **One item per distinct value of `from`'s `identity`** inside the run, each with
    its own window opened by its own earliest `from` and judged by the same rules as
    an ordinary assertion (`:satisfied`/`:violated`/`:pending`/`:suspended`).
  - **An `eventually`/`or_else` occurrence is paired to an item by those same
    identity field values in its own payload** — a hit whose payload does not carry
    them cannot resolve any item. This is the conservative direction to fail in:
    a fact that cannot be told apart from the item it is supposed to resolve does
    not get to resolve it by coincidence.
  - **The run's one reported verdict is the worst of its items':** `:violated` if
    any item's window closed empty, else `:pending` if any is still open, else
    `:suspended` if any was excused, else `:satisfied` — which requires every item to
    be. This is a universal quantifier, and it is the whole point: the promise this
    gap was found on was *every* delivered item, not *some*.

  **`via` is reported only when every item was satisfied through the same route.** A
  run resolved partly by `eventually` and partly by `or_else` reports `via: nil` —
  a real loss of information, not an oversight, because deciding what a mixed route
  means to the process owner is a modelling question the workshop has not been asked,
  not an engineering one this module can answer on its own.

  The ordinary case — `identity` equal to `instance`, one of the thing per run — is
  untouched: same query, same function, same cost. Quantification only runs for the
  shape `PNS.Check` already flags, and today that is exactly one assertion in the
  whole repository (`ProcessShapes.Rig`'s `submission_reaches_inspection`) — the real
  case that found this, Rehmed's payer settlement, still cannot write the assertion
  at all, because its anchoring fact belongs to a different process. Quantification
  does not reach that gap; see `lib/rehmed/contracts/payer_settlement.ex`.

  ## The boundary of the report

  `evaluate/3` returns verdicts **per run**, because that is the only way to count
  them correctly and the only way to test them. Notes §9 also foresee a
  single-run view — for debugging, "what happened to invoice 4712".

  But **the report aggregates to numbers** (`summary/1`). "Which company has no
  open July" is a question about the state of the business and belongs to the
  client application; PNS answers the question about the assertion.
  """

  import Ecto.Query


  alias PNS.Event

  @typedoc "One run's verdict for one assertion."
  @type verdict :: %{
          instance_id: String.t(),
          verdict: :satisfied | :violated | :pending | :suspended,
          via: :eventually | :or_else | nil,
          from_at: DateTime.t(),
          deadline_at: DateTime.t() | nil,
          resolved_at: DateTime.t() | nil
        }

  @doc """
  Verdicts for every run in which this assertion's `from` occurred.

  `now:` allows the assertion to be evaluated at a given moment — without it the
  difference between `:pending` and `:violated` could not be tested.
  """
  @spec evaluate(module(), atom(), keyword()) :: [verdict()]
  def evaluate(contract, trace_name, opts \\ []) do
    trace =
      Enum.find(contract.traces(), &(&1.name == trace_name)) ||
        raise ArgumentError, "#{inspect(contract)} does not declare assertion #{inspect(trace_name)}"

    now = Keyword.get(opts, :now) || DateTime.utc_now()

    # One query for the whole evaluation rather than one per run: an assertion is judged
    # per run, and a query per run would make the report cost grow with the client's
    # traffic. Deliberately **not** bounded by `opts` — an outage is dated by when it was
    # observed, and a report for July has to see an outage observed in July even when the
    # window it asks about was opened by an event from June.
    outages = awaited_outages(contract, trace)

    if quantified?(contract, trace) do
      evaluate_quantified(contract, trace, opts, now, outages)
    else
      evaluate_per_run(contract, trace, opts, now, outages)
    end
  end

  @spec evaluate_per_run(module(), map(), keyword(), DateTime.t(), [DateTime.t()]) :: [verdict()]
  defp evaluate_per_run(contract, trace, opts, now, outages) do
    from_type = to_string(trace.from)

    contract
    |> occurrences(trace, opts)
    |> Enum.flat_map(fn {instance_id, by_type} ->
      case Map.get(by_type, from_type) do
        # A run with no `from` is not evaluated — the assertion is conditional.
        nil -> []
        times -> [verdict(trace, instance_id, Enum.min(times, DateTime), by_type, now, outages)]
      end
    end)
    |> Enum.sort_by(& &1.from_at, DateTime)
  end

  # The same shape `PNS.Check.assertions_finer_than_their_run/1` flags statically: the
  # `from` event is identified by more than its run is, so the run holds several of the
  # thing the assertion is about. Kept local rather than shared with `PNS.Check` — a
  # runtime evaluator reaching into a compile-gate module for a three-line set comparison
  # would be the wrong direction of dependency for a three-line comparison to justify.
  @spec quantified?(module(), map()) :: boolean()
  defp quantified?(contract, trace) do
    event = contract.event(trace.from)
    process = contract.process_of(trace.from)
    event.identity != nil and process != nil and finer?(event.identity, process.instance)
  end

  @spec finer?([atom()], [atom()]) :: boolean()
  defp finer?(identity, instance) do
    identity = MapSet.new(identity)
    instance = MapSet.new(instance)
    MapSet.subset?(instance, identity) and not MapSet.equal?(instance, identity)
  end

  @spec evaluate_quantified(module(), map(), keyword(), DateTime.t(), [DateTime.t()]) :: [verdict()]
  defp evaluate_quantified(contract, trace, opts, now, outages) do
    from_type = to_string(trace.from)

    contract
    |> item_occurrences(trace, opts)
    |> Enum.flat_map(fn {instance_id, by_item} ->
      item_verdicts =
        for {_item_key, by_type} <- by_item,
            times = Map.get(by_type, from_type),
            times != nil do
          verdict(trace, instance_id, Enum.min(times, DateTime), by_type, now, outages)
        end

      # An instance can appear here with no item at all: `item_occurrences/3` groups
      # every row it fetched, including one whose only rows are an `eventually` or
      # `or_else` that happens to share a run but not a single `from`. Same rule as the
      # ordinary path — no `from`, nothing to judge.
      case item_verdicts do
        [] -> []
        verdicts -> [aggregate(instance_id, verdicts)]
      end
    end)
    |> Enum.sort_by(& &1.from_at, DateTime)
  end

  # The run's one verdict is the worst of its items' — a universal quantifier over
  # `:satisfied`, because the promise this exists for is "every item", not "some item".
  # Priority order matches severity to a reader: a broken promise outranks an open one,
  # an open one outranks an excused one, and only when nothing is left unresolved does
  # the run get to be satisfied.
  @spec aggregate(String.t(), [verdict()]) :: verdict()
  defp aggregate(instance_id, item_verdicts) do
    priority = %{violated: 0, pending: 1, suspended: 2, satisfied: 3}
    worst = Enum.min_by(item_verdicts, &priority[&1.verdict])

    %{
      instance_id: instance_id,
      verdict: worst.verdict,
      via: aggregate_via(item_verdicts, worst.verdict),
      from_at: Enum.min_by(item_verdicts, & &1.from_at, DateTime).from_at,
      deadline_at: aggregate_deadline(item_verdicts),
      resolved_at: aggregate_resolved(item_verdicts, worst.verdict)
    }
  end

  # `nil` on purpose when items were satisfied through different routes — the run
  # genuinely was closed two ways, and picking one to report would be inventing an
  # answer to a question the process owner was never asked.
  @spec aggregate_via([verdict()], atom()) :: atom() | nil
  defp aggregate_via(_item_verdicts, verdict) when verdict != :satisfied, do: nil

  defp aggregate_via(item_verdicts, :satisfied) do
    case item_verdicts |> Enum.map(& &1.via) |> Enum.uniq() do
      [only] -> only
      _mixed -> nil
    end
  end

  @spec aggregate_deadline([verdict()]) :: DateTime.t() | nil
  defp aggregate_deadline(item_verdicts) do
    case Enum.reject(item_verdicts, &is_nil(&1.deadline_at)) do
      [] -> nil
      dated -> Enum.max_by(dated, & &1.deadline_at, DateTime).deadline_at
    end
  end

  @spec aggregate_resolved([verdict()], atom()) :: DateTime.t() | nil
  defp aggregate_resolved(_item_verdicts, verdict) when verdict != :satisfied, do: nil
  defp aggregate_resolved(item_verdicts, :satisfied), do: Enum.max_by(item_verdicts, & &1.resolved_at, DateTime).resolved_at

  @doc "Verdicts for every assertion of every registered contract."
  @spec evaluate_all(keyword()) :: [%{contract: module(), trace: atom(), verdicts: [verdict()]}]
  def evaluate_all(opts \\ []) do
    for contract <- PNS.Registry.contracts(), trace <- contract.traces() do
      %{
        contract: contract,
        trace: trace.name,
        verdicts: evaluate(contract, trace.name, opts)
      }
    end
  end

  @doc """
  Verdicts collapsed to numbers — this is the shape that goes into the report.

  `satisfied` is broken down by `via`, because "satisfied through `or_else`" is
  different business information from "satisfied through `eventually`" despite the
  identical verdict: in both cases the agreement was kept, but in one the month
  opened and in the other it stalled.
  """
  @spec summary([verdict()]) :: map()
  def summary(verdicts) do
    %{
      satisfied: count(verdicts, &(&1.verdict == :satisfied)),
      satisfied_via_eventually: count(verdicts, &(&1.via == :eventually)),
      satisfied_via_or_else: count(verdicts, &(&1.via == :or_else)),
      violated: count(verdicts, &(&1.verdict == :violated)),
      pending: count(verdicts, &(&1.verdict == :pending)),
      # Reported separately and never folded into `violated`, which would be the obvious
      # shortcut and the wrong one: these runs are the ones the client is **not**
      # answerable for, so merging them back would undo the whole point of the verdict.
      suspended: count(verdicts, &(&1.verdict == :suspended)),
      instances: length(verdicts)
    }
  end

  @spec count([verdict()], (verdict() -> boolean())) :: non_neg_integer()
  defp count(verdicts, fun), do: Enum.count(verdicts, fun)

  @spec verdict(map(), String.t(), DateTime.t(), map(), DateTime.t(), [DateTime.t()]) :: verdict()
  defp verdict(trace, instance_id, from_at, by_type, now, outages) do
    deadline_at = trace.within && PNS.Duration.shift(from_at, trace.within)
    hit = fn name -> name && first_at_or_after(by_type[to_string(name)], from_at) end

    eventually_at = hit.(trace.eventually)
    or_else_at = hit.(trace.or_else)

    {verdict, via, at} =
      cond do
        in_window?(eventually_at, deadline_at) -> {:satisfied, :eventually, eventually_at}
        in_window?(or_else_at, deadline_at) -> {:satisfied, :or_else, or_else_at}
        pending?(deadline_at, now) -> {:pending, nil, nil}
        # Last, so a suspension can only ever take the place of a violation. Reached only
        # when the window has passed and nothing arrived.
        suspended?(outages, from_at, deadline_at) -> {:suspended, nil, nil}
        true -> {:violated, nil, nil}
      end

    %{
      instance_id: instance_id,
      verdict: verdict,
      via: via,
      from_at: from_at,
      deadline_at: deadline_at,
      resolved_at: at
    }
  end

  # The unavailability moments that could explain **this** assertion failing: the ones
  # belonging to dependencies declared by the events that were awaited and did not arrive.
  #
  # `from` is left out on purpose. It happened, so whatever it depends on was working — and
  # including it would suspend runs on the strength of an outage that demonstrably did not
  # stop anything. Taking every dependency in the contract would be worse still: a run
  # would be excused because something it never touched was down.
  @spec awaited_outages(module(), map()) :: [DateTime.t()]
  defp awaited_outages(contract, trace) do
    observed = PNS.Dependency.observations_by_external(contract)

    for name <- [trace.eventually, trace.or_else],
        name != nil,
        external = contract.event(name).depends_on,
        external != nil,
        at <- Map.get(observed, to_string(external), []) do
      at
    end
  end

  # An assertion with no `within` never reaches this — it cannot be violated, so there is
  # nothing for a suspension to take the place of.
  @spec suspended?([DateTime.t()], DateTime.t(), DateTime.t() | nil) :: boolean()
  defp suspended?(_outages, _from_at, nil), do: false

  defp suspended?(outages, from_at, deadline_at) do
    Enum.any?(outages, fn at ->
      DateTime.compare(at, from_at) != :lt and DateTime.compare(at, deadline_at) != :gt
    end)
  end

  @spec in_window?(DateTime.t() | nil, DateTime.t() | nil) :: boolean()
  defp in_window?(nil, _deadline_at), do: false
  # An assertion with no `within` has no deadline, so it cannot be violated — any
  # occurrence satisfies it. Such an assertion is unfalsifiable, and that is
  # recorded in PLAN.md as a candidate for an `info` in `pns.check`.
  defp in_window?(_at, nil), do: true
  defp in_window?(at, deadline_at), do: DateTime.compare(at, deadline_at) != :gt

  @spec pending?(DateTime.t() | nil, DateTime.t()) :: boolean()
  defp pending?(nil, _now), do: true
  defp pending?(deadline_at, now), do: DateTime.compare(now, deadline_at) == :lt

  @spec first_at_or_after([DateTime.t()] | nil, DateTime.t()) :: DateTime.t() | nil
  defp first_at_or_after(nil, _from_at), do: nil

  defp first_at_or_after(times, from_at) do
    times
    |> Enum.filter(&(DateTime.compare(&1, from_at) != :lt))
    |> Enum.min(DateTime, fn -> nil end)
  end

  @spec occurrences(module(), map(), keyword()) :: %{String.t() => %{String.t() => [DateTime.t()]}}
  defp occurrences(contract, trace, opts) do
    types =
      [trace.from, trace.eventually, trace.or_else]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&to_string/1)

    query =
      from(e in Event,
        where: e.contract == ^inspect(contract),
        where: e.type in ^types,
        where: not is_nil(e.instance_id),
        select: {e.instance_id, e.type, e.occurred_at}
      )

    query
    |> maybe_since(Keyword.get(opts, :since))
    |> maybe_until(Keyword.get(opts, :until))
    |> maybe_instance(Keyword.get(opts, :instance))
    |> repo().all()
    |> Enum.group_by(fn {instance, _t, _at} -> instance end, fn {_i, type, at} -> {type, at} end)
    |> Map.new(fn {instance, pairs} ->
      {instance, Enum.group_by(pairs, &elem(&1, 0), &elem(&1, 1))}
    end)
  end

  # Same query shape as `occurrences/3`, deliberately not shared with it: this one
  # also selects `payload`, because pairing an occurrence to an item needs the values
  # of `from`'s identity fields wherever they appear. Folding that column into the
  # ordinary query would make every non-quantified evaluation — the overwhelming
  # majority — fetch a column it never reads.
  @spec item_occurrences(module(), map(), keyword()) ::
          %{String.t() => %{tuple() => %{String.t() => [DateTime.t()]}}}
  defp item_occurrences(contract, trace, opts) do
    types =
      [trace.from, trace.eventually, trace.or_else]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&to_string/1)

    identity = contract.event(trace.from).identity |> Enum.map(&to_string/1)

    query =
      from(e in Event,
        where: e.contract == ^inspect(contract),
        where: e.type in ^types,
        where: not is_nil(e.instance_id),
        select: {e.instance_id, e.type, e.occurred_at, e.payload}
      )

    query
    |> maybe_since(Keyword.get(opts, :since))
    |> maybe_until(Keyword.get(opts, :until))
    |> maybe_instance(Keyword.get(opts, :instance))
    |> repo().all()
    |> Enum.group_by(fn {instance, _t, _at, _p} -> instance end)
    |> Map.new(fn {instance, rows} ->
      by_item =
        rows
        |> Enum.group_by(
          fn {_i, _t, _at, payload} -> item_key(payload, identity) end,
          fn {_i, type, at, _p} -> {type, at} end
        )
        |> Map.new(fn {key, pairs} -> {key, Enum.group_by(pairs, &elem(&1, 0), &elem(&1, 1))} end)

      {instance, by_item}
    end)
  end

  # A tuple of raw values, not a joined string: two payload fields have no separator
  # to escape or collide on if they are never joined in the first place, which is a
  # cheaper way to avoid the exact class of bug closed elsewhere today in `PNS.Instance`
  # and `PNS.Job`.
  @spec item_key(map(), [String.t()]) :: tuple()
  defp item_key(payload, identity), do: identity |> Enum.map(&Map.get(payload, &1)) |> List.to_tuple()

  @spec maybe_since(Ecto.Query.t(), DateTime.t() | nil) :: Ecto.Query.t()
  defp maybe_since(query, nil), do: query
  defp maybe_since(query, since), do: where(query, [e], e.occurred_at >= ^since)

  @spec maybe_until(Ecto.Query.t(), DateTime.t() | nil) :: Ecto.Query.t()
  defp maybe_until(query, nil), do: query
  defp maybe_until(query, until), do: where(query, [e], e.occurred_at <= ^until)

  @spec maybe_instance(Ecto.Query.t(), String.t() | nil) :: Ecto.Query.t()
  defp maybe_instance(query, nil), do: query
  defp maybe_instance(query, id), do: where(query, [e], e.instance_id == ^id)

  # **Read at run time, not at compile time — and that changed when the engine
  # became its own application (2026-08-20).** `Application.compile_env!/2`
  # resolved to the host's repo module while compiling this package, and a package
  # compiles before the application that configures it: every call site warned that
  # the host's repo module was undefined, and in a real consumer it would warn about
  # theirs. A library cannot hold a compile-time reference to a module its user
  # has not written yet.
  #
  # What is lost is `compile_env!`'s check that configuration has not changed since
  # the build. What is gained is that this compiles standing alone, which is the
  # whole point of a package.
  defp repo, do: Application.fetch_env!(:pns, :repo)
end
