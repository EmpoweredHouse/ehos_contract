defmodule EhOsContract.CheckKeysTest do
  @moduledoc """
  The two static checks that compare **a fact's key** with **its run's key**.

  `identity` says what makes two occurrences the same fact; `instance` says what
  makes two events the same run. Almost every real contract writes one as a superset
  of the other and nobody ever looks again — which is exactly why the comparison
  itself has to be pinned. The contracts in this repository are all supersets, so
  neither check has ever had to say anything, and a check whose only evidence is its
  own silence is not tested.

  ## Why the fixtures are here and not in `test/support/`

  Each contract below exists to be a modelling error. In `test/support/` it would
  join the registry, and then every `mix eh_os_contract.check` in this repository would carry a
  warning about a fixture built to be warned about — which is how a check gets
  switched off. So the checks take an explicit list of contracts and these are handed
  to them directly.
  """

  use ExUnit.Case, async: true

  defmodule PermutedKey do
    @moduledoc """
    A key written in another order. **Not** an error: `[:b, :a]` and `[:a, :b]`
    identify the same thing.
    """

    use EhOsContract.Contract

    event :thing_started,
      label: "Thing started",
      payload: %{a: :id, b: :id},
      identity: [:b, :a],
      process: :thing

    event :thing_finished,
      label: "Thing finished",
      payload: %{a: :id, b: :id},
      process: :thing,
      terminal: true

    trace :thing_finishes do
      from :thing_started
      eventually :thing_finished, within: {1, :day}
    end

    process :thing, label: "Thing", instance: [:a, :b]
  end

  defmodule FinerKey do
    @moduledoc "A genuinely finer key: many of these facts fit in one run."

    use EhOsContract.Contract

    event :item_started,
      label: "Item started",
      payload: %{a: :id, b: :id},
      identity: [:a, :b],
      process: :thing

    event :item_finished,
      label: "Item finished",
      payload: %{a: :id, b: :id},
      process: :thing,
      terminal: true

    trace :item_finishes do
      from :item_started
      eventually :item_finished, within: {1, :day}
    end

    process :thing, label: "Thing", instance: [:a]
  end

  defmodule DisjointKey do
    @moduledoc "A fact keyed by something its run knows nothing about."

    use EhOsContract.Contract

    event :note_taken,
      label: "Note taken",
      payload: %{a: :id, x: :id},
      identity: [:x],
      process: :thing

    process :thing, label: "Thing", instance: [:a]
  end

  defmodule PartialKey do
    @moduledoc "A fact keyed by half of its run — the shape a two-field run invites."

    use EhOsContract.Contract

    event :note_taken,
      label: "Note taken",
      payload: %{a: :id, b: :id, x: :id},
      identity: [:a, :x],
      process: :thing

    process :thing, label: "Thing", instance: [:a, :b]
  end

  describe "an assertion finer than its run" do
    test "a key written in another order is not finer, because it is the same key" do
      # If this fails, every contract that happens to spell its `identity` in a
      # different order from its `instance` is reported as making a per-item promise
      # over a per-run window. The reader's only available fix — reordering a keyword
      # list — changes nothing, so the warning cannot be cleared and gets ignored;
      # and once it is ignored, the real granularity finding beside it is ignored too.
      assert EhOsContract.Check.assertions_finer_than_their_run([PermutedKey]) == []
    end

    test "a strictly finer key is still reported" do
      # The control. Without it the test above would pass against a check that had
      # simply stopped finding anything.
      assert [finding] = EhOsContract.Check.assertions_finer_than_their_run([FinerKey])
      assert finding.trace == :item_finishes
      assert finding.identity == [:a, :b]
      assert finding.instance == [:a]
    end
  end

  describe "a fact whose key does not contain its run" do
    test "a key disjoint from the run is reported" do
      # Unreported, this is a fact that cannot say which run it belongs to. The
      # asynchronous idempotency key is built from `identity` alone, so the same `x`
      # occurring under two different `a` values produces one key: the client's
      # idempotency table reads the second fact as a repeat, its handler never runs,
      # and both events sit in the log looking handled.
      assert [finding] = EhOsContract.Check.facts_not_keyed_by_their_run([DisjointKey])
      assert finding.event == :note_taken
      assert finding.missing == [:a]
    end

    test "a key containing only part of the run is reported, and names the part that is missing" do
      # The half-covered case is the likelier one in practice — a run keyed by two
      # fields where the fact's author remembered one. Naming the missing field is
      # what makes the finding actionable rather than an accusation.
      assert [finding] = EhOsContract.Check.facts_not_keyed_by_their_run([PartialKey])
      assert finding.missing == [:b]
    end

    test "a key that contains its run is not reported, whichever order it is written in" do
      # Two controls in one: the ordinary superset case, and the permutation. The
      # second matters because this check does its own set arithmetic, so it could
      # acquire the same order-sensitivity that the neighbouring check had.
      assert EhOsContract.Check.facts_not_keyed_by_their_run([FinerKey, PermutedKey]) == []
    end

    test "the repository's own contracts produce nothing" do
      # The evidence that this check is not merely finding fixtures built for it.
      # Every contract here keys its facts by a superset of its run; if one stops
      # doing so, that is a finding rather than a reason to relax the test.
      assert EhOsContract.Check.facts_not_keyed_by_their_run() == []
    end
  end
end
