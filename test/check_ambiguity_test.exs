defmodule PNS.CheckAmbiguityTest do
  @moduledoc """
  **The silent-green family: four ways this engine ends a run looking healthy.**

  Every case here produces a report a reader would accept. That is the whole reason
  they are worth more than the loud failures beside them: the product's one asset is
  that its green means something, and each of these spends it.

  | What | What it looks like |
  | --- | --- |
  | Two contracts declaring one event name | handlers of a foreign process run inside your transaction, and nothing says so |
  | Two contracts declaring one process name | one process's runs counted as another's, in a column that cannot be separated afterwards |
  | No contracts at all | `0 errors, 0 warnings, 0 notices` — the same line a clean repository prints |
  | An assertion with no `within` | satisfied or pending for ever, never violated |

  The fixtures are declared here rather than in `test/support/` on purpose: each is a
  contract built to be wrong, and in `test/support/` it would join the registry and
  put a permanent finding on every `mix pns.check` in this repository. The checks take
  an explicit contract list so they can be handed one directly.
  """

  use Taxvision.DataCase, async: false

  defmodule TwinEventA do
    @moduledoc "Invented. Declares a name a second contract also declares."

    use PNS.Contract

    event :thing_happened,
      label: "Thing happened",
      payload: %{a: :id},
      process: :first

    process :first, label: "First", instance: [:a]
  end

  defmodule TwinEventB do
    @moduledoc "Invented. The other declarer of `thing_happened`."

    use PNS.Contract

    event :thing_happened,
      label: "A different thing, with the same name",
      payload: %{b: :id},
      process: :second

    process :second, label: "Second", instance: [:b]
  end

  defmodule TwinProcessA do
    @moduledoc "Invented. Its process shares a name with the next contract's."

    use PNS.Contract

    event :a_happened, label: "A happened", payload: %{case_id: :id}, process: :shared

    process :shared, label: "Shared", instance: [:case_id]
  end

  defmodule TwinProcessB do
    @moduledoc "Invented. The other declarer of process `:shared`."

    use PNS.Contract

    event :b_happened, label: "B happened", payload: %{case_id: :id}, process: :shared

    process :shared, label: "Shared, and unrelated", instance: [:case_id]
  end

  defmodule NoDeadline do
    @moduledoc "Invented. An assertion with nothing that could refute it."

    use PNS.Contract

    event :asked, label: "Asked", payload: %{case_id: :id}, process: :asking
    event :answered, label: "Answered", payload: %{case_id: :id}, process: :asking, terminal: true

    trace :an_answer_arrives do
      from :asked
      eventually :answered
    end

    process :asking, label: "Asking", instance: [:case_id]
  end

  defmodule Doppelganger do
    @moduledoc """
    Invented, and the sharpest fixture in this file.

    It declares `item_measured` — a name `ProcessShapes.Rig` already uses — and its
    own unrelated process. It is **not** in the registry, and it does not need to be:
    handlers are selected by event name alone, so the rig's handlers answer an event
    this contract emits.
    """

    use PNS.Contract

    event :item_measured,
      label: "A shipment was measured, which is not what the rig means by this name",
      payload: %{shipment_id: :id},
      process: :shipping

    process :shipping, label: "Shipping", instance: [:shipment_id]
  end

  defmodule PairingTwin do
    @moduledoc "Invented. Its process is named `:pairing`, which the rig also declares."

    use PNS.Contract

    event :shipment_paired, label: "Shipment paired", payload: %{case_id: :id}, process: :pairing

    process :pairing, label: "Pairing, but somebody else's", instance: [:case_id]
  end

  describe "two contracts declaring one event name" do
    test "the check reports it" do
      assert [collision] = PNS.Check.event_names_declared_twice([TwinEventA, TwinEventB])
      assert collision.name == :thing_happened
      assert collision.contracts == Enum.sort([TwinEventA, TwinEventB])
    end

    test "a foreign contract's handlers run on it, which is what the check is about" do
      # This is the damage, demonstrated rather than argued. `Doppelganger` is not in
      # the registry and shares nothing with `ProcessShapes.Rig` except the string
      # `item_measured` — and the rig's two handlers run anyway, inside this emission's
      # transaction, against a payload the rig never declared.
      #
      # If this stops being true the check above can be deleted. While it is true, a
      # duplicate event name means somebody else's consequences fire on your facts and
      # the only visible trace is a handling row in a table nobody reads.
      event = PNS.emit!(Doppelganger, :item_measured, %{shipment_id: "s-1"})

      handlers =
        Repo.all(from h in PNS.EventHandling, where: h.event_id == ^event.id, select: h.handler)

      assert "ProcessShapes.Intake.OnItemMeasuredFirst" in handlers
      assert "ProcessShapes.Intake.OnItemMeasuredSecond" in handlers
    end

    test "the repository's own contracts declare no name twice" do
      # The control, and the reason the check is not merely finding its own fixtures.
      assert PNS.Check.event_names_declared_twice() == []
    end
  end

  describe "two contracts declaring one process name" do
    test "the check reports it" do
      assert [collision] = PNS.Check.process_names_declared_twice([TwinProcessA, TwinProcessB])
      assert collision.name == :shared
    end

    test "their runs are literally the same run key" do
      # `PNS.Instance` builds `"<process>|<values>"` and puts no contract in it, so
      # this is not a near-miss — it is one string. Two unrelated processes then share
      # the `instance_id` column, and no query written afterwards can take them apart,
      # because the distinguishing information was never written.
      assert PNS.Instance.key(TwinProcessA, :a_happened, %{case_id: "c-1"}) ==
               PNS.Instance.key(TwinProcessB, :b_happened, %{case_id: "c-1"})
    end

    test "events from two contracts land in one run in the log" do
      # The same thing at the level a report reads it. `PNS.Graph.overlay/1` counts
      # runs per process **name**, so this row inflates the denominator every path
      # report for `:pairing` divides by — coverage improves because a stranger emitted
      # something.
      PNS.emit!(ProcessShapes.Rig, :item_measured, %{case_id: "c-1", item_no: 1})
      PNS.emit!(PairingTwin, :shipment_paired, %{case_id: "c-1"})

      contracts =
        Repo.all(from e in PNS.Event, where: e.instance_id == "pairing|c-1", select: e.contract)

      assert "ProcessShapes.Rig" in contracts
      assert "PNS.CheckAmbiguityTest.PairingTwin" in contracts
    end

    test "the repository's own contracts declare no process name twice" do
      assert PNS.Check.process_names_declared_twice() == []
    end
  end

  describe "nothing to check" do
    test "an empty registry is recognised as such" do
      # Without this, a scan pointed at the wrong application prints the same three
      # zeroes as a clean build. It is not a hypothetical: it is what this engine did
      # the first time it compiled as its own package, scanning itself.
      assert PNS.Check.no_contracts?([])
    end

    test "this repository has something to check" do
      # The control. A predicate that answered "empty" for everything would satisfy the
      # test above and silence the whole task.
      refute PNS.Check.no_contracts?()
    end
  end

  describe "an assertion with no deadline" do
    test "the check reports it" do
      assert [finding] = PNS.Check.unfalsifiable_assertions([NoDeadline])
      assert finding.trace == :an_answer_arrives
    end

    test "and it can never be violated, however long nothing happens" do
      # The reason the finding is worth printing. A year after the question, with no
      # answer anywhere in the log, the verdict is still `:pending` — which reads as
      # "too early to say" and will read that way for ever, because the window a
      # violation has to be past never closes.
      Repo.insert!(%PNS.Event{
        type: "asked",
        contract: inspect(NoDeadline),
        contract_version: NoDeadline.version(),
        process: "asking",
        instance_id: "asking|c-1",
        correlation_id: Ecto.UUID.generate(),
        payload: %{"case_id" => "c-1"},
        occurred_at: ~U[2026-01-01 00:00:00.000000Z]
      })

      assert [verdict] =
               PNS.Trace.evaluate(NoDeadline, :an_answer_arrives, now: ~U[2027-01-01 00:00:00.000000Z])

      assert verdict.verdict == :pending
      assert verdict.deadline_at == nil
    end

    test "every assertion in this repository has a deadline" do
      # The control, and a claim worth keeping true: the four real contracts all bound
      # their promises, so this check currently finds nothing and any future line it
      # prints is a new declaration rather than a backlog.
      assert PNS.Check.unfalsifiable_assertions() == []
    end
  end
end
