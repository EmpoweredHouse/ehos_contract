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

  ## One limitation, and it fails towards good news

  **An assertion is per run, so a promise made per item inside a run is
  mis-measured rather than refused.** One verdict is produced per instance: the
  window opens on the first `from` in that run and closes on the first hit after
  it. Where the run holds many of the thing being promised about, one match
  satisfies the whole run.

  The compile gates catch a `trace` spanning two processes and a calendar unit in
  `within`. **Nothing catches granularity.** Found while distilling Rehmed's
  monthly payer settlement (`Rehmed.Contracts.PayerSettlement`), where a run is one
  payer in one month and the promise — every delivered visit is invoiced or
  excluded with a reason — is about each visit in it. Forty unsettled visits behind
  one settled one report as satisfied.

  The workaround is to key the process by the thing the promise is about, which is
  usually right anyway: `instance` is what an assertion is counted within, so a
  promise finer than the instance is a sign the instance is wrong. That is not
  always available — the anchoring fact may already belong to another process — and
  when it is not, there is currently nothing to write. Recorded rather than
  approximated, and tracked in `PLAN.md`.

  ## The boundary of the report

  `evaluate/3` returns verdicts **per run**, because that is the only way to count
  them correctly and the only way to test them. Notes §9 also foresee a
  single-run view — for debugging, "what happened to invoice 4712".

  But **the report aggregates to numbers** (`summary/1`). "Which company has no
  open July" is a question about the state of the business and belongs to the
  client application; PNS answers the question about the assertion.
  """

  import Ecto.Query

  @repo Application.compile_env!(:pns_prototype, :repo)

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
    from_type = to_string(trace.from)

    # One query for the whole evaluation rather than one per run: an assertion is judged
    # per run, and a query per run would make the report cost grow with the client's
    # traffic. Deliberately **not** bounded by `opts` — an outage is dated by when it was
    # observed, and a report for July has to see an outage observed in July even when the
    # window it asks about was opened by an event from June.
    outages = awaited_outages(contract, trace)

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

  @spec maybe_since(Ecto.Query.t(), DateTime.t() | nil) :: Ecto.Query.t()
  defp maybe_since(query, nil), do: query
  defp maybe_since(query, since), do: where(query, [e], e.occurred_at >= ^since)

  @spec maybe_until(Ecto.Query.t(), DateTime.t() | nil) :: Ecto.Query.t()
  defp maybe_until(query, nil), do: query
  defp maybe_until(query, until), do: where(query, [e], e.occurred_at <= ^until)

  @spec maybe_instance(Ecto.Query.t(), String.t() | nil) :: Ecto.Query.t()
  defp maybe_instance(query, nil), do: query
  defp maybe_instance(query, id), do: where(query, [e], e.instance_id == ^id)

  defp repo, do: @repo
end
