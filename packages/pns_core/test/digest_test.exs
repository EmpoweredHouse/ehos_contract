defmodule PNS.DigestTest do
  @moduledoc """
  Stage 2.4: **a canonical contract hash.**

  The version stamped on an event is compared against a hash recomputed weeks later,
  so the requirement is narrow and absolute: the same agreement hashes the same way,
  always. `:erlang.term_to_binary/1` serialises a runtime representation rather than
  a value, so it could not promise that across OTP releases — and a moved hash
  reclassifies the whole log as belonging to an older agreement, which is the
  evidence report announcing a contract change on a day nothing changed.

  The fixtures below are declared **inside this file on purpose**. The registry scans
  the application's module list, and modules defined in a `.exs` are not in it — so
  these contracts are invisible to the graph, the deployment table and every path
  report. A fixture that exists to be hashed should not turn up in a client's report
  as an unobserved process.
  """

  use ExUnit.Case, async: true

  defmodule Ordered do
    @moduledoc false
    use PNS.Contract

    event :first, label: "Pierwsze", payload: %{case_id: :id, seq: :integer}
    event :second, label: "Drugie", payload: %{case_id: :id, seq: :integer}
  end

  defmodule Reordered do
    @moduledoc false
    use PNS.Contract

    # The same two declarations, swapped. This is an ordinary edit — nobody would
    # expect it to change what was agreed.
    event :second, label: "Drugie", payload: %{case_id: :id, seq: :integer}
    event :first, label: "Pierwsze", payload: %{case_id: :id, seq: :integer}
  end

  defmodule Changed do
    @moduledoc false
    use PNS.Contract

    # One payload type differs. That *is* a change to the agreement.
    event :first, label: "Pierwsze", payload: %{case_id: :id, seq: :string}
    event :second, label: "Drugie", payload: %{case_id: :id, seq: :integer}
  end

  describe "the contract version" do
    test "does not move when declarations are only reordered" do
      # The likelier of the two defects the old hash had, and the reason this is
      # worth a module: an OTP upgrade is an event somebody notices, moving an
      # `event` block up two lines is not.
      assert Ordered.version() == Reordered.version()
    end

    test "moves when a declaration actually changes" do
      # The control. Without it the test above would also pass for a hash that
      # returned a constant.
      refute Ordered.version() == Changed.version()
    end

    test "is twelve hex characters, so it can be read out of a report" do
      assert Ordered.version() =~ ~r/^[0-9a-f]{12}$/
    end
  end

  describe "the canonical form" do
    test "sorts map keys, so encoding order cannot leak into the hash" do
      # Not reachable through map literals — equal maps are equal — so the property
      # is pinned on the canonical string, which is where it actually lives.
      assert PNS.Digest.canonical(%{b: 1, a: 2}) == "{a:a=n:2,a:b=n:1}"
    end

    test "keeps the order of a list, because a declaration depends on it" do
      # `instance: [:company_id, :period]` is not the same agreement as its reverse:
      # the run key is those values joined in order. Sorting here would make two
      # different run keys hash alike.
      refute PNS.Digest.canonical([:a, :b]) == PNS.Digest.canonical([:b, :a])
    end

    test "does not let values of different kinds collide" do
      assert PNS.Digest.canonical(:x) != PNS.Digest.canonical("x")
      assert PNS.Digest.canonical(1) != PNS.Digest.canonical("1")
      assert PNS.Digest.canonical([:a]) != PNS.Digest.canonical({:a})
    end

    test "canonicalises a struct rather than raising a protocol error" do
      # A struct is a map without being enumerable, so the naive implementation
      # raises `Protocol.UndefinedError` in the middle of compiling somebody's
      # contract. No declaration holds a struct today, which is exactly why this
      # would have been found late.
      assert PNS.Digest.canonical(%PNS.Emission{name: :x, payload: %{}}) =~ "PNS.Emission"
    end
  end

  describe "grouped declarations" do
    test "an empty group is not the same as a group with something in it" do
      a = PNS.Digest.hash_groups(events: [%{name: :x}], externals: [])
      b = PNS.Digest.hash_groups(events: [], externals: [%{name: :x}])

      refute a == b
    end

    test "member order within a group is insignificant" do
      a = PNS.Digest.hash_groups(events: [%{name: :x}, %{name: :y}])
      b = PNS.Digest.hash_groups(events: [%{name: :y}, %{name: :x}])

      assert a == b
    end
  end
end
