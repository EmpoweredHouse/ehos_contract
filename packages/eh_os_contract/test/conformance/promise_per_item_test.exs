defmodule EhOsContract.PromisePerItemTest do
  @moduledoc """
  **A promise made per item inside a run, and how it is counted** — on a v2
  contract (plan E11a), where `trace_granularity_test.exs` pinned it for v1.

  Found while distilling Rehmed's monthly payer settlement: a run is one payer in one
  month, and the promise is about each delivered visit in it. Since 21 August 2026 a
  run's one verdict requires every item in it to be resolved, and a hit counts only
  for the item it concerns (`EhOsContract.Trace`'s moduledoc has the mechanism).

  A v2 promise takes that path when the unit of its `from` event has an identity
  strictly finer than the process's `correlate` (`finer?/2` in `EhOsContract.Trace`).
  Until this file no v2 fixture had that shape, so the path had never run for a v2
  contract. Here the unit is an item, keyed by case and number, and the run is the
  case.

  v1's static check that named the shape before any data existed
  (`assertions_finer_than_their_run/1`) has no v2 counterpart on purpose: in v2 the
  shape is the ordinary reading of a unit inside a run, not a warning.

  Invented, and out of the registry for the same reason as `promise_edges_test.exs`.
  """

  use EhOsContract.DataCase, async: false

  alias EhOsContract.Trace

  defmodule Domain do
    @moduledoc "# INVENTED. NOT A DOMAIN."

    use EhOsContract.Domain, name: :promise_per_item, language: :en

    context :inspection, "Inspection", subdomain: :core
    actor :inspector, :system, "Inspector"
    subdomain :core, "Core", type: :core
  end

  defmodule PerItem do
    @moduledoc """
    # INVENTED. NOT A DOMAIN.

    Items of one case, each submitted and then inspected or rejected.
    """

    use EhOsContract.Contract,
      domain: EhOsContract.PromisePerItemTest.Domain,
      context: :inspection,
      id: "promise_per_item.per_item"

    aggregate :item, "Item" do
      identity [:case_id, :item_no]

      event :item_submitted, "Item submitted", recorded_by: :inspector
      event :item_inspected, "Item inspected", recorded_by: :inspector
      event :item_rejected, "Item rejected", recorded_by: :inspector
    end

    process :inspection, "Inspection" do
      correlate :case_id

      promise :item_inspected_within_a_day do
        from :item_submitted
        eventually :item_inspected
        within {1, :day}
      end

      # Two ways to close an item, for the test that mixes them.
      promise :item_resolved do
        from :item_submitted
        eventually :item_inspected
        within {1, :day}
        or_else :item_rejected
      end

      # No `within`, for the test where a deadline is never computed at all.
      promise :item_acknowledged do
        from :item_submitted
        eventually :item_inspected
      end
    end
  end

  @submitted ~U[2026-07-01 09:00:00.000000Z]
  # `within {1, :day}`, so the window closes a day after `@submitted`.
  @inside_window ~U[2026-07-01 15:00:00.000000Z]
  @after_window ~U[2026-07-05 09:00:00.000000Z]

  # Through the store, so the append puts the event in its run (see
  # `promise_edges_test.exs`).
  defp insert(name, case_id, item_no, at) do
    repo = Application.fetch_env!(:eh_os_contract, :repo)

    entry = %{
      type: "promise_per_item.per_item.#{name}",
      contract: EhOsContract.Model.fetch(PerItem).id,
      contract_version: EhOsContract.Model.fetch(PerItem).version,
      process: "inspection",
      instance_id: "inspection|#{case_id}",
      correlation_id: Ecto.UUID.generate(),
      actor: EhOsContract.Event.system_actor(),
      payload: %{"case_id" => case_id, "item_no" => item_no},
      occurred_at: at
    }

    {:ok, {:ok, [event]}} =
      repo.transaction(fn -> EhOsContract.Store.append(repo, [entry], :none) end)

    event
  end

  defp submit(case_id, item_no, at \\ @submitted),
    do: insert(:item_submitted, case_id, item_no, at)

  defp inspected(case_id, item_no, at), do: insert(:item_inspected, case_id, item_no, at)

  defp verdicts(promise \\ :item_inspected_within_a_day),
    do: Trace.evaluate(PerItem, promise, now: @after_window)

  describe "a run's one verdict requires every item to be resolved" do
    test "three items promised, one delivered — the run is violated" do
      for item_no <- 1..3, do: submit("c-1", item_no)
      inspected("c-1", 1, @inside_window)

      assert [verdict] = verdicts()

      assert verdict.verdict == :violated,
             "two of three items were never inspected, and the promise is not fully kept"
    end

    test "the fulfilment must be about the same item, not merely inside the run" do
      # Item 3's inspection resolves item 3 alone; items 1 and 2 are still owed.
      for item_no <- 1..3, do: submit("c-1", item_no)
      inspected("c-1", 3, @inside_window)

      assert [verdict] = verdicts()
      assert verdict.verdict == :violated
    end

    test "one verdict per run even though it counts several items" do
      for item_no <- 1..10, do: submit("c-1", item_no)
      inspected("c-1", 1, @inside_window)

      assert length(verdicts()) == 1,
             "counting per item changes what counts towards the verdict, not how many come out"
    end

    test "every item delivered — the run is satisfied, and via is uniform" do
      for item_no <- 1..3, do: submit("c-1", item_no)
      for item_no <- 1..3, do: inspected("c-1", item_no, @inside_window)

      assert [verdict] = verdicts()
      assert verdict.verdict == :satisfied
      assert verdict.via == :eventually
    end

    test "the control: with nothing delivered the run is violated" do
      # Without this, a mechanism that never says `violated` would pass the tests above
      # for a duller reason.
      for item_no <- 1..3, do: submit("c-1", item_no)

      assert [verdict] = verdicts()
      assert verdict.verdict == :violated
    end

    test "a broken promise outranks one still open — the run is violated, not pending" do
      # Item 1's window closed with nothing; item 2 is submitted at `now`, so its own
      # window is still open. The promise was "every item", and one already missed it.
      submit("c-2", 1, @submitted)
      submit("c-2", 2, @after_window)

      assert [verdict] = verdicts()
      assert verdict.verdict == :violated
    end

    test "satisfied through different routes reports via: nil, not a guess" do
      submit("c-3", 1)
      inspected("c-3", 1, @inside_window)
      submit("c-3", 2)
      insert(:item_rejected, "c-3", 2, @inside_window)

      assert [verdict] = verdicts(:item_resolved)
      assert verdict.verdict == :satisfied

      assert verdict.via == nil,
             "one item closed via eventually and the other via or_else — either alone would invent an answer"
    end

    test "no `within` — the run's deadline is nil, not invented" do
      # Item 2 was never inspected and, with no `within`, is unfalsifiable rather than
      # violated, so the run is pending and there is no deadline anywhere to report.
      submit("c-4", 1)
      inspected("c-4", 1, @inside_window)
      submit("c-4", 2)

      assert [verdict] = verdicts(:item_acknowledged)
      assert verdict.verdict == :pending
      assert verdict.deadline_at == nil
    end

    test "an occurrence with no matching item anywhere in its run produces no verdict" do
      # An inspection with no submission behind it, in a run with no submission either:
      # there is no item to attach it to and nothing to judge.
      inspected("c-orphan", 1, @inside_window)

      assert verdicts() == []
    end
  end
end
