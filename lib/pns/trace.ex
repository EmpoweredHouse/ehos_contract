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

  ## Three verdicts, and a fourth that does not exist yet

  | Verdict | Meaning |
  |---|---|
  | `:satisfied` | `eventually` **or** `or_else` occurred inside the window |
  | `:violated` | the window passed and neither occurred |
  | `:pending` | the window has not passed yet — nothing is known |

  **`:satisfied` carries `via:`** — `:eventually` or `:or_else`. That is the whole
  subtlety of this assertion and the easiest thing to get wrong: blocking the
  month is a **correct ending**, just not the one we wanted. The verdict has to
  read "satisfied", and the report has to be able to say by which route — because
  a tool that shouts about every correctly blocked month gets switched off within
  a week.

  The fourth verdict — `:suspended`, an adapter's unavailability window — is
  **not here and cannot be computed**: nothing in the system records that an
  external dependency was unavailable. `unavailable_looks_like` in the contract is
  a sentence nobody reads today. Details and the prerequisite are in `PLAN.md`,
  stage 1.5b. Until then a registry outage inside an assertion window counts as
  `:violated`, which blames the client for someone else's server. That is known
  and recorded, not hidden.

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
          verdict: :satisfied | :violated | :pending,
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

    contract
    |> occurrences(trace, opts)
    |> Enum.flat_map(fn {instance_id, by_type} ->
      case Map.get(by_type, from_type) do
        # A run with no `from` is not evaluated — the assertion is conditional.
        nil -> []
        times -> [verdict(trace, instance_id, Enum.min(times, DateTime), by_type, now)]
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
      instances: length(verdicts)
    }
  end

  @spec count([verdict()], (verdict() -> boolean())) :: non_neg_integer()
  defp count(verdicts, fun), do: Enum.count(verdicts, fun)

  @spec verdict(map(), String.t(), DateTime.t(), map(), DateTime.t()) :: verdict()
  defp verdict(trace, instance_id, from_at, by_type, now) do
    deadline_at = trace.within && PNS.Duration.shift(from_at, trace.within)
    hit = fn name -> name && first_at_or_after(by_type[to_string(name)], from_at) end

    eventually_at = hit.(trace.eventually)
    or_else_at = hit.(trace.or_else)

    {verdict, via, at} =
      cond do
        in_window?(eventually_at, deadline_at) -> {:satisfied, :eventually, eventually_at}
        in_window?(or_else_at, deadline_at) -> {:satisfied, :or_else, or_else_at}
        pending?(deadline_at, now) -> {:pending, nil, nil}
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
