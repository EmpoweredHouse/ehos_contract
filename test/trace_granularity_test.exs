defmodule PNS.TraceGranularityTest do
  @moduledoc """
  **A promise made per item inside a run is mis-measured, not refused — and it
  fails towards good news.**

  Found while distilling Rehmed's monthly payer settlement, where a run is one
  payer in one month and the promise is about each delivered visit in it: *every
  delivered payer-funded visit is either included in that period's invoice, or
  excluded with a stated reason.* Its failure costs money in both directions and
  the client names both.

  An assertion produces **one verdict per instance**. The window opens on the first
  `from` in the run and closes on the first hit at or after it, so one fulfilment
  satisfies the whole run however many items were promised about.

  ## Why this is worse than a refusal

  The compile gates catch a `trace` spanning two processes and a calendar unit in
  `within` — both loudly, at build time. This one compiles, emits, evaluates, and
  reports `satisfied`. The report's only asset is being believed, and this is the
  cheapest way to spend it.

  ## What these tests are

  The first two **pin the defect as it stands today**, so that a fix is detected
  rather than assumed. Read them as a description of what happens, never as what
  should happen — the names say so.

  The third is tagged `:known_defect` and is **excluded from the default run**, so
  `mix check` stays green while a literal red test exists on demand:

      mix test --include known_defect

  It asserts the behaviour we want. When the engine grows a way to express a
  per-item promise, that test turns green and the two above turn red, which is the
  correct direction for all three.

  ## Exercised on the shapes rig, and it needed no new fixture

  `ProcessShapes.Rig` already has the shape: `submission_reaches_inspection` runs
  between two **per-item** events — `item_submitted` and `item_inspected`, both
  keyed `[:case_id, :item_no]` — inside a process whose `instance` is `[:case_id]`
  alone. The rig exists to hold process shapes; this is one it was already holding
  without anybody noticing.
  """

  use Taxvision.DataCase, async: false

  alias ProcessShapes.Rig

  @trace :submission_reaches_inspection
  @submitted ~U[2026-07-01 09:00:00.000000Z]
  # `within: {1, :day}` on the rig's assertion, so the window closes here.
  @inside_window ~U[2026-07-01 15:00:00.000000Z]
  @after_window ~U[2026-07-05 09:00:00.000000Z]

  defp insert(type, case_id, item_no, at) do
    Repo.insert!(%PNS.Event{
      type: type,
      contract: inspect(Rig),
      contract_version: Rig.version(),
      process: "pairing",
      instance_id: "pairing|#{case_id}",
      correlation_id: Ecto.UUID.generate(),
      payload: %{"case_id" => case_id, "item_no" => item_no},
      occurred_at: at
    })
  end

  defp submit(case_id, item_no, at \\ @submitted), do: insert("item_submitted", case_id, item_no, at)
  defp inspected(case_id, item_no, at), do: insert("item_inspected", case_id, item_no, at)

  defp verdicts, do: PNS.Trace.evaluate(Rig, @trace, now: @after_window)

  describe "the gap, as it behaves today" do
    test "three items promised, one delivered — and the run reports SATISFIED" do
      for item_no <- 1..3, do: submit("c-1", item_no)
      inspected("c-1", 1, @inside_window)

      assert [verdict] = verdicts()

      assert verdict.verdict == :satisfied,
             """
             This assertion is the defect, not the requirement.

             Two of the three submitted items were never inspected, and the report
             says the agreement was kept. If this line ever fails, the engine has
             learnt to count per item — delete it and enable the `:known_defect`
             test below.
             """

      assert verdict.via == :eventually
    end

    test "the fulfilment need not even be the item that opened the window" do
      # Item 1 opens the window and is never inspected. Item 3 is, inside the
      # window — and that is enough, because the evaluator looks for the first
      # occurrence of the target at or after the first occurrence of the source
      # and never compares the two payloads.
      #
      # This is the sharper half of the finding: it is not merely that one hit
      # covers many promises, it is that the hit and the promise need not be about
      # the same thing at all.
      for item_no <- 1..3, do: submit("c-1", item_no)
      inspected("c-1", 3, @inside_window)

      assert [verdict] = verdicts()
      assert verdict.verdict == :satisfied
    end

    test "one verdict per run, whatever the number of items — which is the cause" do
      for item_no <- 1..10, do: submit("c-1", item_no)
      inspected("c-1", 1, @inside_window)

      assert length(verdicts()) == 1,
             "the granularity of a verdict is the instance, and that is the whole of it"
    end

    test "the control: with nothing delivered the run is correctly violated" do
      # Without this the tests above would prove nothing — a mechanism that never
      # says `violated` would report satisfied for a different and duller reason.
      for item_no <- 1..3, do: submit("c-1", item_no)

      assert [verdict] = verdicts()
      assert verdict.verdict == :violated
    end
  end

  describe "what it should do" do
    @tag :known_defect
    test "three items promised and one delivered is not a kept agreement" do
      for item_no <- 1..3, do: submit("c-1", item_no)
      inspected("c-1", 1, @inside_window)

      assert [verdict] = verdicts()

      refute verdict.verdict == :satisfied,
             "two of three items were never inspected and the agreement is reported as kept"
    end
  end
end
