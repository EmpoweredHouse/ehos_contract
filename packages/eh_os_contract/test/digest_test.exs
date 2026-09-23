defmodule EhOsContract.DigestTest do
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
    use EhOsContract.Contract

    event :first, label: "Pierwsze", payload: %{case_id: :id, seq: :integer}
    event :second, label: "Drugie", payload: %{case_id: :id, seq: :integer}
  end

  defmodule Reordered do
    @moduledoc false
    use EhOsContract.Contract

    # The same two declarations, swapped. This is an ordinary edit — nobody would
    # expect it to change what was agreed.
    event :second, label: "Drugie", payload: %{case_id: :id, seq: :integer}
    event :first, label: "Pierwsze", payload: %{case_id: :id, seq: :integer}
  end

  defmodule Changed do
    @moduledoc false
    use EhOsContract.Contract

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
      assert EhOsContract.Digest.canonical(%{b: 1, a: 2}) == "{a:a=n:2,a:b=n:1}"
    end

    test "keeps the order of a list, because a declaration depends on it" do
      # `instance: [:company_id, :period]` is not the same agreement as its reverse:
      # the run key is those values joined in order. Sorting here would make two
      # different run keys hash alike.
      refute EhOsContract.Digest.canonical([:a, :b]) == EhOsContract.Digest.canonical([:b, :a])
    end

    test "does not let values of different kinds collide" do
      assert EhOsContract.Digest.canonical(:x) != EhOsContract.Digest.canonical("x")
      assert EhOsContract.Digest.canonical(1) != EhOsContract.Digest.canonical("1")
      assert EhOsContract.Digest.canonical([:a]) != EhOsContract.Digest.canonical({:a})
    end

    test "canonicalises a struct rather than raising a protocol error" do
      # A struct is a map without being enumerable, so the naive implementation
      # raises `Protocol.UndefinedError` in the middle of compiling somebody's
      # contract. No declaration holds a struct today, which is exactly why this
      # would have been found late.
      assert EhOsContract.Digest.canonical(%EhOsContract.Emission{name: :x, payload: %{}}) =~
               "EhOsContract.Emission"
    end
  end

  defmodule WithCommand do
    @moduledoc false
    use EhOsContract.Contract

    event :first, label: "Pierwsze", payload: %{case_id: :id, seq: :integer}, process: :p
    command :start_it, label: "Start it", process: :p, principals: [:human]
    process :p, label: "P", instance: [:case_id]
  end

  defmodule WithoutCommand do
    @moduledoc false
    use EhOsContract.Contract

    event :first, label: "Pierwsze", payload: %{case_id: :id, seq: :integer}, process: :p
    process :p, label: "P", instance: [:case_id]
  end

  describe "the seventh declaration group" do
    test "a declared command moves the contract version" do
      # The group is in `hash_groups/1`'s keyword list, and this is what says so.
      # Without it the whole seventh declaration could be added to a contract with
      # no effect on its recorded version, and the log would keep classifying events
      # under an agreement that had changed.
      refute WithCommand.version() == WithoutCommand.version()
    end

    test "and gets its own entry among the declaration digests" do
      assert Map.has_key?(WithCommand.declaration_digests(), "command:start_it")
      refute Map.has_key?(WithoutCommand.declaration_digests(), "command:start_it")
    end
  end

  describe "per-declaration digests" do
    test "every named declaration gets an entry, plus one for the examples" do
      # Derived rather than a literal: `ProcessShapes.Rig`'s own moduledoc warns that
      # adding an event moves counts a dozen tests assert against, and this test has
      # no opinion about how many declarations a fixture holds — only that none is
      # missing.
      contract = ProcessShapes.Rig

      expected =
        length(contract.events()) + length(contract.processes()) + length(contract.traces()) +
          length(contract.externals()) + length(contract.rules()) + 1

      assert map_size(contract.declaration_digests()) == expected
      assert Map.has_key?(contract.declaration_digests(), "process:pairing")
    end

    test "does not move when declarations are only reordered" do
      # The same property `version/0` has, for the same reason: moving an `event`
      # block up two lines is an edit, not a change to the agreement.
      assert Ordered.declaration_digests() == Reordered.declaration_digests()
    end

    test "a changed declaration moves its own entry and no other" do
      # This is the whole point. `version/0` only says something moved; here the
      # changed payload type is attributable to `event:first` and `event:second` is
      # demonstrably untouched.
      ordered = Ordered.declaration_digests()
      changed = Changed.declaration_digests()

      refute ordered["event:first"] == changed["event:first"]
      assert ordered["event:second"] == changed["event:second"]
    end

    test "each entry is twelve hex characters, like the contract version" do
      for {_key, digest} <- Ordered.declaration_digests() do
        assert digest =~ ~r/^[0-9a-f]{12}$/
      end
    end
  end

  describe "grouped declarations" do
    test "adding an empty group moves the hash" do
      # Unpinned until now, and it is the whole argument for landing a seventh
      # declaration in one commit: a contract that declares no commands still gets a
      # new `version/0` the day the `command` group exists, so history reclassifies
      # once — deliberately — rather than twice.
      a = EhOsContract.Digest.hash_groups(events: [%{name: :x}])
      b = EhOsContract.Digest.hash_groups(events: [%{name: :x}], commands: [])

      refute a == b
    end

    test "an empty group is not the same as a group with something in it" do
      a = EhOsContract.Digest.hash_groups(events: [%{name: :x}], externals: [])
      b = EhOsContract.Digest.hash_groups(events: [], externals: [%{name: :x}])

      refute a == b
    end

    test "member order within a group is insignificant" do
      a = EhOsContract.Digest.hash_groups(events: [%{name: :x}, %{name: :y}])
      b = EhOsContract.Digest.hash_groups(events: [%{name: :y}, %{name: :x}])

      assert a == b
    end
  end
end
