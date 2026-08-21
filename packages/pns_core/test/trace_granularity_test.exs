defmodule PNS.TraceGranularityTest do
  @moduledoc """
  **A promise made per item inside a run, and how it is counted.**

  Found while distilling Rehmed's monthly payer settlement, where a run is one
  payer in one month and the promise is about each delivered visit in it: *every
  delivered payer-funded visit is either included in that period's invoice, or
  excluded with a stated reason.* Its failure costs money in both directions and
  the client names both.

  **Fixed 21 August 2026.** Until then an assertion produced one verdict per
  instance regardless of how many of the promised thing occurred inside it: the
  window opened on the first `from` in the run and closed on the first hit after
  it, so one fulfilment satisfied the whole run however many items were promised
  about — and the hit did not even have to concern the same item, because nothing
  compared payloads. See `PNS.Trace`'s moduledoc for the mechanism.

  ## What these tests are now

  The first block used to pin the defect as it stood; it now pins the fix — every
  test that used to assert `:satisfied` on partial delivery now asserts the
  opposite, and the names say so. The rest are new, covering the aggregation the
  fix introduced: the all-resolved case, the mixed-route case, and the priority
  between a broken promise and one still open.

  ## Exercised on the shapes rig, and it needed no new fixture

  `ProcessShapes.Rig` already has the shape: `submission_reaches_inspection` runs
  between two **per-item** events — `item_submitted` and `item_inspected`, both
  keyed `[:case_id, :item_no]` — inside a process whose `instance` is `[:case_id]`
  alone. The rig exists to hold process shapes; this is one it was already holding
  without anybody noticing. The mixed-route test needs an `or_else`, which the
  rig's assertion does not declare, so it uses a small local fixture instead —
  same reasoning as `test/job_idempotency_test.exs`: adding a second per-item
  assertion to the shared rig would give `PNS.Check.assertions_finer_than_their_run/1`
  two findings instead of one, which is exactly what
  "the static check" block below exists to keep true.
  """

  use PNS.DataCase, async: false

  alias ProcessShapes.Rig

  defmodule MixedRoute do
    @moduledoc """
    INVENTED, local to this file. A per-item promise with two ways to close it —
    `submission_reaches_inspection` on the shared rig only has `eventually`, and
    the mixed-route test below needs an `or_else` to have two routes to mix.
    """

    use PNS.Contract

    event :piece_submitted,
      label: "Piece submitted",
      payload: %{batch_id: :id, piece_no: :integer},
      identity: [:batch_id, :piece_no],
      process: :batching

    event :piece_approved,
      label: "Piece approved",
      payload: %{batch_id: :id, piece_no: :integer},
      identity: [:batch_id, :piece_no],
      process: :batching

    event :piece_rejected,
      label: "Piece rejected",
      payload: %{batch_id: :id, piece_no: :integer},
      identity: [:batch_id, :piece_no],
      process: :batching

    trace :piece_is_resolved do
      from :piece_submitted
      eventually :piece_approved, within: {1, :day}
      or_else :piece_rejected
    end

    # No `within`, for the test that needs an assertion where a deadline is never
    # computed at all — see "no `within` on the assertion" below.
    trace :piece_is_acknowledged do
      from :piece_submitted
      eventually :piece_approved
    end

    process :batching, label: "Batching", instance: [:batch_id]
  end

  @submitted ~U[2026-07-01 09:00:00.000000Z]
  # `within: {1, :day}` on the rig's assertion, so the window closes here.
  @inside_window ~U[2026-07-01 15:00:00.000000Z]
  @after_window ~U[2026-07-05 09:00:00.000000Z]

  defp insert(contract, type, process, instance_id, payload, at) do
    Repo.insert!(%PNS.Event{
      type: type,
      contract: inspect(contract),
      contract_version: contract.version(),
      process: process,
      instance_id: instance_id,
      correlation_id: Ecto.UUID.generate(),
      payload: payload,
      occurred_at: at
    })
  end

  defp submit(case_id, item_no, at \\ @submitted),
    do: insert(Rig, "item_submitted", "pairing", "pairing|#{case_id}", %{"case_id" => case_id, "item_no" => item_no}, at)

  defp inspected(case_id, item_no, at),
    do: insert(Rig, "item_inspected", "pairing", "pairing|#{case_id}", %{"case_id" => case_id, "item_no" => item_no}, at)

  defp verdicts, do: PNS.Trace.evaluate(Rig, :submission_reaches_inspection, now: @after_window)

  describe "quantification: a run's one verdict now requires every item to be resolved" do
    test "three items promised, one delivered — the run is violated" do
      for item_no <- 1..3, do: submit("c-1", item_no)
      inspected("c-1", 1, @inside_window)

      assert [verdict] = verdicts()

      assert verdict.verdict == :violated,
             "two of three items were never inspected, and the agreement is not fully kept"
    end

    test "the fulfilment must be about the same item, not merely inside the run" do
      # Item 1 opens the window and is never inspected. Item 3 is, inside the window —
      # and that used to be enough, because the evaluator looked for the first
      # occurrence of the target at or after the first occurrence of the source and
      # never compared the two payloads. Now a hit is paired to an item by its own
      # identity field values, so item 3's inspection resolves item 3 alone.
      for item_no <- 1..3, do: submit("c-1", item_no)
      inspected("c-1", 3, @inside_window)

      assert [verdict] = verdicts()
      assert verdict.verdict == :violated
    end

    test "one verdict per run even though it counts several items" do
      for item_no <- 1..10, do: submit("c-1", item_no)
      inspected("c-1", 1, @inside_window)

      assert length(verdicts()) == 1,
             "quantification changes what counts towards the verdict, not how many verdicts come out"
    end

    test "every item delivered — the run is satisfied, and via is uniform" do
      for item_no <- 1..3, do: submit("c-1", item_no)
      for item_no <- 1..3, do: inspected("c-1", item_no, @inside_window)

      assert [verdict] = verdicts()
      assert verdict.verdict == :satisfied
      assert verdict.via == :eventually
    end

    test "the control: with nothing delivered the run is violated" do
      # Without this the tests above would prove nothing — a mechanism that never
      # says `violated` would report satisfied for a different and duller reason.
      for item_no <- 1..3, do: submit("c-1", item_no)

      assert [verdict] = verdicts()
      assert verdict.verdict == :violated
    end

    test "a broken promise outranks one still open — the run is violated, not pending" do
      # Item 1's window has already closed with nothing. Item 2 is submitted right at
      # `now`, so its own window has not closed yet. A run cannot be reported as merely
      # `:pending` while a different item in it has already failed — the promise was
      # "every item", and one of them is already known to have missed it.
      submit("c-2", 1, @submitted)
      submit("c-2", 2, @after_window)

      assert [verdict] = verdicts()
      assert verdict.verdict == :violated
    end

    test "satisfied through different routes reports via: nil, not a guess" do
      insert(MixedRoute, "piece_submitted", "batching", "batching|b-1", %{"batch_id" => "b-1", "piece_no" => 1}, @submitted)
      insert(MixedRoute, "piece_approved", "batching", "batching|b-1", %{"batch_id" => "b-1", "piece_no" => 1}, @inside_window)
      insert(MixedRoute, "piece_submitted", "batching", "batching|b-1", %{"batch_id" => "b-1", "piece_no" => 2}, @submitted)
      insert(MixedRoute, "piece_rejected", "batching", "batching|b-1", %{"batch_id" => "b-1", "piece_no" => 2}, @inside_window)

      assert [verdict] =
               PNS.Trace.evaluate(MixedRoute, :piece_is_resolved, now: @after_window)

      assert verdict.verdict == :satisfied

      assert verdict.via == nil,
             "one piece closed via eventually and the other via or_else — reporting either alone would invent an answer"
    end

    test "no `within` on the assertion — the aggregate deadline is nil, not invented" do
      insert(MixedRoute, "piece_submitted", "batching", "batching|b-2", %{"batch_id" => "b-2", "piece_no" => 1}, @submitted)
      insert(MixedRoute, "piece_approved", "batching", "batching|b-2", %{"batch_id" => "b-2", "piece_no" => 1}, @inside_window)
      insert(MixedRoute, "piece_submitted", "batching", "batching|b-2", %{"batch_id" => "b-2", "piece_no" => 2}, @submitted)

      assert [verdict] =
               PNS.Trace.evaluate(MixedRoute, :piece_is_acknowledged, now: @after_window)

      # Piece 1 is resolved; piece 2 was never approved and, with no `within`, is
      # unfalsifiable rather than violated — the same "info, not violated" rule an
      # ordinary assertion without `within` already gets. So the run is pending, not
      # violated, and there is no deadline anywhere to report.
      assert verdict.verdict == :pending
      assert verdict.deadline_at == nil
    end

    test "an occurrence with no matching item anywhere in its run produces no verdict" do
      # `item_occurrences/3` groups every row it fetched for the run, including this
      # one — an inspection with no submission at all behind it, in a run that has no
      # submission either. There is no item to attach it to and nothing to judge.
      inspected("c-orphan", 1, @inside_window)

      assert PNS.Trace.evaluate(Rig, :submission_reaches_inspection, now: @after_window) == []
    end
  end

  describe "the static check that names it before any data exists" do
    test "the rig's assertion is reported as finer than its run" do
      # This is the whole point of `PNS.Check.assertions_finer_than_their_run/1`:
      # the tests above need a log to demonstrate the shape, and the check needs
      # only the declarations. `identity` says two occurrences are different facts;
      # `instance` says they belong to one run. Strictly finer means the run holds
      # several, so an assertion anchored there is counted over several items and
      # is now evaluated that way.
      findings = PNS.Check.assertions_finer_than_their_run()

      assert %{
               contract: ProcessShapes.Rig,
               trace: :submission_reaches_inspection,
               from: :item_submitted,
               identity: [:case_id, :item_no],
               process: :pairing,
               instance: [:case_id]
             } in findings
    end

    test "and it is the only one in the repository, so the check is not noise" do
      # Both Rehmed assertions anchor on `visit_completed`, which declares no
      # `identity` at all because a visit ends once. Nothing to compare, nothing
      # reported — a check that fired on those would be worse than none. `MixedRoute`
      # above is not in the registry (it lives in this `.exs` file, not under an
      # application the registry scans), so it does not add a second finding here.
      assert [_only_one] = PNS.Check.assertions_finer_than_their_run()
    end
  end
end
