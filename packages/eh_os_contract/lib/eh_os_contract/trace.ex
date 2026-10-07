defmodule EhOsContract.Trace do
  @moduledoc """
  Evaluation of a process's `promise`s **per run**.

  This is where anything at run time **reads** a promise. Without it a promise
  would be declared in the contract and checked only for whether its event names
  exist — that is, prose in Elixir syntax. The log knows what happened; this asks
  whether that agrees with the contract.

  A promise reads like this:

      promise :month_opens_or_is_blocked do
        from :data_completeness_confirmed
        eventually :accounting_month_opened
        within {2, :day}
        or_else :registry_discrepancy_detected
      end

  *"After the data set is confirmed complete, within two days the month either
  opens or a registry discrepancy is detected."*

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
  and adds nothing, which is why the recording behind it (`EhOsContract.Dependency`) is deliberately
  reluctant: over-recording unavailability would quietly stop reporting real problems.

  **Which dependency counts is narrow: the ones declared by the events that did not
  arrive.** `from` already happened, so whatever it needed was working. What blocked the
  run is whatever `eventually` or `or_else` depends on. Taking the union of the whole
  contract's dependencies would suspend a run because something unrelated was down.

  **This union is `eventually`'s dependency `or` `or_else`'s, not their intersection —
  decided rather than assumed, 21 August 2026.** A narrower reading was on the table: a
  wanted route with no dependency at all can never be blocked by an outage, so suspend
  only when every still-possible route was. Rejected, because the promise is the
  disjunction itself — "X or Y" — and here Y was impossible, which stands as a reason
  to withhold judgement on the run even when X depended on nothing.
  `test/conformance/promise_edges_test.exs` pins this.

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

  When the unit identity of `from`'s event is strictly finer than the process's
  correlation, the run holds more than one of the thing the promise is about, and
  `trace/2` sets its `identity` and `judge/3` switches modes:

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

  The ordinary case — the identity equal to the correlation, one of the thing per
  run — is untouched: same query, same function, same cost.

  ## The boundary of the report

  `evaluate/3` returns verdicts **per run**, because that is the only way to count
  them correctly and the only way to test them. Notes §9 also foresee a
  single-run view — for debugging, "what happened to invoice 4712".

  ## A pure core, and the log around it

  The rules above live in `judge/3`, which takes a `trace/0` and the events to judge
  and reads neither the log nor the clock. `trace/2` reads the trace from the
  contract; `evaluate/3` is the two of them over the log's rows and the recorded
  outages. So a verdict can be asked of events that never reached a log — a
  scenario's, a test's — and it is the same verdict the report would give.

  ## The runs

  A contract declares `promise` in its one `process` (v2 §13, plan E7c). The runs
  are the rows of `eh_os_contract_event_runs` for that process, so an event another
  contract decided and this one includes counts in its run (D7), and the events are
  named by their stored types, `"<contract id>.<event>"`.
  `test/conformance/promise_test.exs` pins the verdicts.

  But **the report aggregates to numbers** (`summary/1`). "Which company has no
  open July" is a question about the state of the business and belongs to the
  client application; EhOsContract answers the question about the assertion.
  """

  import Ecto.Query

  alias EhOsContract.{Event, EventRun, Model}

  @typedoc "One run's verdict for one promise."
  @type verdict :: %{
          instance_id: String.t(),
          verdict: :satisfied | :violated | :pending | :suspended,
          via: :eventually | :or_else | nil,
          from_at: DateTime.t(),
          deadline_at: DateTime.t() | nil,
          resolved_at: DateTime.t() | nil
        }

  @typedoc """
  What a promise is judged on, read from the contract once by `trace/2`: the stored
  types of its three events, its window, and — for a promise made per item inside a
  run — the payload fields that tell one item from another.

  `identity` is `nil` for the ordinary promise, one of the thing per run. It belongs
  to the trace and not to the call because it is a fact about the contract: a caller
  that had to pass it could leave it out, and judge a per-item promise per run without
  meaning to.
  """
  @type trace :: %{
          from: String.t(),
          eventually: String.t(),
          or_else: String.t() | nil,
          within: {pos_integer(), atom()} | nil,
          identity: [String.t()] | nil
        }

  @typedoc """
  One event a promise is judged on, with the run it belongs to. `payload` is read only
  when the trace has an `identity`, to pair the event with its item, and may be left
  out otherwise. It is the payload as the log stores it, with string keys. An
  `eventually` or `or_else` whose payload does not carry every identity field, or
  carries one as `nil`, resolves no item; a `from` like that still opens one, so that
  an obligation is never dropped for want of a field.
  """
  @type occurrence :: %{
          required(:instance_id) => String.t(),
          required(:type) => String.t(),
          required(:occurred_at) => DateTime.t(),
          optional(:payload) => map()
        }

  @doc """
  Verdicts for every run in which this promise's `from` occurred.

  `now:` allows the promise to be evaluated at a given moment — without it the
  difference between `:pending` and `:violated` could not be tested. `since:`,
  `until:` and `instance:` narrow the events read from the log.

  This is `trace/2`, the log's rows and the recorded outages, handed to `judge/3`.
  """
  @spec evaluate(module(), atom(), keyword()) :: [verdict()]
  def evaluate(contract, name, opts \\ []) do
    model = Model.fetch(contract)
    trace = trace(model, name)

    judge(trace, occurrences(model, trace, opts),
      now: Keyword.get(opts, :now) || DateTime.utc_now(),
      # Deliberately **not** bounded by `opts` — an outage is dated by when it was
      # observed, and a report for July has to see an outage observed in July even when
      # the window it asks about was opened by an event from June.
      outages: promised_outages(model, promise!(model, name))
    )
  end

  @doc """
  The trace of a contract's `promise` (v2 §13): what `judge/3` needs from the
  contract, and nothing from the log.

  Its events are named by their stored types, `"<contract id>.<event>"` — the sibling's
  for an event the contract includes (D7). Its `identity` is set when the unit of
  `from`'s event is strictly finer than the process's correlation, which is when the
  promise is made per item inside a run.

  Raises `ArgumentError` when the contract declares no such promise, and for a domain,
  which declares none.
  """
  @spec trace(module() | map(), atom()) :: trace()
  def trace(contract, name) do
    model = Model.fetch(contract)
    promise = promise!(model, name)

    trace = %{
      from: stored_type!(model, promise.from),
      eventually: stored_type!(model, promise.eventually),
      or_else: promise.or_else && stored_type!(model, promise.or_else),
      within: promise.within && {promise.within.amount, promise.within.unit}
    }

    identity = identity_of(model, promise.from)

    Map.put(
      trace,
      :identity,
      if(finer?(identity, Model.process(model).correlate), do: Enum.map(identity, &to_string/1))
    )
  end

  @doc """
  Verdicts for every run in `occurrences` in which the trace's `from` occurred — the
  rules of this module, over events given rather than read. Pure: it reads neither
  the log nor the clock, so the same events judged at the same moment always give
  the same verdicts.

  - `now:` (required) — the moment of judgement, which tells `:pending` from
    `:violated`.
  - `outages:` — the moments a dependency of `eventually` or `or_else` was seen
    unavailable; a window that closed empty with one inside it is `:suspended`.
    Defaults to none.

  Occurrences of types other than the trace's three are ignored. For a trace with an
  `identity`, every occurrence needs its `payload`, keyed by strings as the log stores
  it; one without a payload, or with an identity field under an atom key, raises
  `ArgumentError` naming the field — read as missing, it would pair every such event
  with every other and resolve items it is not about. An `eventually` or `or_else`
  without every identity field is about no item, and is left out.
  """
  @spec judge(trace(), [occurrence()], keyword()) :: [verdict()]
  def judge(trace, occurrences, opts) do
    now = Keyword.fetch!(opts, :now)
    outages = Keyword.get(opts, :outages, [])
    types = types(trace)
    occurrences = Enum.filter(occurrences, &(&1.type in types))

    case trace.identity do
      nil -> judge_per_run(trace, occurrences, now, outages)
      identity -> judge_quantified(trace, occurrences, identity, now, outages)
    end
  end

  @spec promise!(map(), atom()) :: map()
  defp promise!(model, name) do
    # A domain's model has no process to ask, and is refused by name like a contract
    # that declares no such promise.
    process = Model.process(model)

    (process && Enum.find(process.promises, &(&1.name == name))) ||
      raise ArgumentError, "#{inspect(model.module)} does not declare promise #{inspect(name)}"
  end

  @spec stored_type!(map(), atom()) :: String.t()
  defp stored_type!(model, name) do
    case Model.declaring(model, name) do
      {_contract, %{type: type}} -> type
      nil -> raise ArgumentError, "#{inspect(model.module)} stores no event #{inspect(name)}"
    end
  end

  # The fields that tell one of the thing apart in its unit: its unit's identity, in
  # the contract that declares the event.
  @spec identity_of(map(), atom()) :: [atom()]
  defp identity_of(model, name) do
    {contract, event} = Model.declaring(model, name)
    Enum.find(Model.fetch(contract).units, &(&1.name == event.unit)).identity
  end

  # The unavailability moments that could explain **this** promise failing: the ones
  # belonging to the externals the events that were awaited and did not arrive depend
  # on, as observed by the contract that declares each.
  #
  # `from` is left out on purpose. It happened, so whatever it depends on was working —
  # and including it would suspend runs on the strength of an outage that demonstrably
  # did not stop anything. Taking every dependency in the contract would be worse
  # still: a run would be excused because something it never touched was down.
  @spec promised_outages(map(), map()) :: [DateTime.t()]
  defp promised_outages(model, promise) do
    for name <- [promise.eventually, promise.or_else],
        name != nil,
        {contract, event} = Model.declaring(model, name),
        external = event.depends_on,
        external != nil,
        at <-
          Map.get(
            EhOsContract.Dependency.observations_by_external(contract),
            to_string(external),
            []
          ) do
      at
    end
  end

  @spec judge_per_run(trace(), [occurrence()], DateTime.t(), [DateTime.t()]) :: [verdict()]
  defp judge_per_run(trace, occurrences, now, outages) do
    from_type = trace.from

    occurrences
    |> Enum.group_by(& &1.instance_id)
    |> Map.new(fn {instance, rows} -> {instance, by_type(rows)} end)
    |> Enum.flat_map(fn {instance_id, by_type} ->
      case Map.get(by_type, from_type) do
        # A run with no `from` is not evaluated — the assertion is conditional.
        nil -> []
        times -> [verdict(trace, instance_id, Enum.min(times, DateTime), by_type, now, outages)]
      end
    end)
    |> Enum.sort_by(& &1.from_at, DateTime)
  end

  @spec finer?([atom()], [atom()]) :: boolean()
  defp finer?(identity, instance) do
    identity = MapSet.new(identity)
    instance = MapSet.new(instance)
    MapSet.subset?(instance, identity) and not MapSet.equal?(instance, identity)
  end

  @spec judge_quantified(trace(), [occurrence()], [String.t()], DateTime.t(), [DateTime.t()]) ::
          [verdict()]
  defp judge_quantified(trace, occurrences, identity, now, outages) do
    from_type = trace.from

    occurrences
    |> by_item(trace, identity)
    |> Enum.flat_map(fn {instance_id, by_item} ->
      item_verdicts =
        for {_item_key, by_type} <- by_item,
            times = Map.get(by_type, from_type),
            times != nil do
          verdict(trace, instance_id, Enum.min(times, DateTime), by_type, now, outages)
        end

      # An instance can appear here with no item at all: `by_item/3` groups every
      # occurrence it keeps, including a run whose only ones are an `eventually` or
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

  defp aggregate_resolved(item_verdicts, :satisfied),
    do: Enum.max_by(item_verdicts, & &1.resolved_at, DateTime).resolved_at

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
    deadline_at = trace.within && EhOsContract.Duration.shift(from_at, trace.within)
    hit = fn type -> type && first_at_or_after(by_type[type], from_at) end

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
  # recorded in PLAN.md as a candidate for an `info` in `eh_os_contract.check`.
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

  # Each run's occurrences grouped by item, then by type. An item is a tuple of the
  # trace's identity values in the occurrence's own payload, so an `eventually` or
  # `or_else` is paired to the item it carries and to no other.
  @spec by_item([occurrence()], trace(), [String.t()]) ::
          %{String.t() => %{tuple() => %{String.t() => [DateTime.t()]}}}
  defp by_item(occurrences, trace, identity) do
    occurrences
    |> Enum.group_by(& &1.instance_id)
    |> Map.new(fn {instance, rows} ->
      by_item =
        rows
        |> Enum.map(&{item_key(&1, identity), &1})
        # A hit that does not name its item resolves none: grouped under a key with
        # `nil` in it, it would pair with a `from` missing the same field and close an
        # item neither names. A `from` like that still opens its item, as it always has,
        # so the obligation is judged rather than dropped.
        |> Enum.reject(fn {key, row} -> row.type != trace.from and nil in Tuple.to_list(key) end)
        |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
        |> Map.new(fn {key, rows} -> {key, by_type(rows)} end)

      {instance, by_item}
    end)
  end

  # Occurrences' moments, by their type, in the order they were given.
  @spec by_type([occurrence()]) :: %{String.t() => [DateTime.t()]}
  defp by_type(occurrences), do: Enum.group_by(occurrences, & &1.type, & &1.occurred_at)

  # A tuple of raw values, not a joined string: two payload fields have no separator
  # to escape or collide on if they are never joined in the first place, which is a
  # cheaper way to avoid a separator colliding with a value than escaping one.
  #
  # The error names the field, never a value: a payload may hold personal data.
  @spec item_key(occurrence(), [String.t()]) :: tuple()
  defp item_key(%{payload: payload}, identity) when is_map(payload) do
    identity
    |> Enum.map(fn field ->
      if atom_key?(payload, field),
        do:
          raise(
            ArgumentError,
            "an occurrence's payload holds #{field} under an atom key; " <>
              "give it as the log stores it, with string keys"
          )

      Map.get(payload, field)
    end)
    |> List.to_tuple()
  end

  defp item_key(_occurrence, identity),
    do:
      raise(
        ArgumentError,
        "an occurrence of a promise made per item needs its payload, " <>
          "to pair it with its item by #{Enum.join(identity, ", ")}"
      )

  # No atom of that name exists, so no payload holds it as a key: a trace handed to
  # `judge/3` may name a field this node never made an atom of, and
  # `String.to_existing_atom/1` would raise on it instead of reading the string key.
  defp atom_key?(payload, field) do
    Map.has_key?(payload, String.to_existing_atom(field))
  rescue
    ArgumentError -> false
  end

  @spec types(trace()) :: [String.t()]
  defp types(trace) do
    Enum.reject([trace.from, trace.eventually, trace.or_else], &is_nil/1)
  end

  # The rows a promise is judged on, as `occurrence()`s: the rows of
  # `eh_os_contract_event_runs` for the contract's one process, whichever contract
  # decided the event, so an event another contract decided counts in a run that
  # includes it (D7).
  #
  # `payload` is selected only for a trace with an `identity`, because pairing an
  # occurrence to an item needs the values of `from`'s identity fields wherever they
  # appear. Selecting it always would make every ordinary evaluation — the
  # overwhelming majority — fetch a column it never reads.
  @spec occurrences(map(), trace(), keyword()) :: [occurrence()]
  defp occurrences(model, trace, opts) do
    process = Atom.to_string(Model.process(model).name)
    types = types(trace)

    query =
      from(r in EventRun,
        as: :run,
        join: e in Event,
        as: :event,
        on: e.position == r.position,
        where: r.process == ^process,
        where: e.type in ^types
      )
      |> bounded(opts)
      |> maybe_instance(Keyword.get(opts, :instance))
      |> select([run: r, event: e], %{
        instance_id: r.instance_id,
        type: e.type,
        occurred_at: e.occurred_at
      })

    query =
      if trace.identity,
        do: select_merge(query, [event: e], %{payload: e.payload}),
        else: query

    repo().all(query)
  end

  @spec bounded(Ecto.Query.t(), keyword()) :: Ecto.Query.t()
  defp bounded(query, opts) do
    query
    |> maybe_since(Keyword.get(opts, :since))
    |> maybe_until(Keyword.get(opts, :until))
  end

  @spec maybe_since(Ecto.Query.t(), DateTime.t() | nil) :: Ecto.Query.t()
  defp maybe_since(query, nil), do: query
  defp maybe_since(query, since), do: where(query, [event: e], e.occurred_at >= ^since)

  @spec maybe_until(Ecto.Query.t(), DateTime.t() | nil) :: Ecto.Query.t()
  defp maybe_until(query, nil), do: query
  defp maybe_until(query, until), do: where(query, [event: e], e.occurred_at <= ^until)

  @spec maybe_instance(Ecto.Query.t(), String.t() | nil) :: Ecto.Query.t()
  defp maybe_instance(query, nil), do: query
  defp maybe_instance(query, id), do: where(query, [run: r], r.instance_id == ^id)

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
  defp repo, do: EhOsContract.Config.fetch!(:repo)
end
