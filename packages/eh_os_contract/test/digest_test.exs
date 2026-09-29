defmodule EhOsContract.DigestTest do
  @moduledoc """
  Stage 2.4: **a canonical contract hash.**

  The version stamped on an event is compared against a hash recomputed weeks later,
  so the requirement is narrow and absolute: the same agreement hashes the same way,
  always. `:erlang.term_to_binary/1` serialises a runtime representation rather than
  a value, so it could not promise that across OTP releases — and a moved hash
  reclassifies the whole log as belonging to an older agreement, which is the
  evidence report announcing a contract change on a day nothing changed.

  What is pinned here is the hash itself: the canonical form, the grouping of
  declarations and the document hash. That a contract's digests have the shape the
  deployment table stores is pinned on a contract, in `dsl/contract_test.exs`.
  """

  use ExUnit.Case, async: true

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
      assert EhOsContract.Digest.canonical(%EhOsContract.Meta{actor: "u-1"}) =~
               "EhOsContract.Meta"
    end
  end

  describe "exported document hashes" do
    test "length-prefix strings, so delimiters cannot make different documents collide" do
      left = ["Wizyta", "Pacjent"]
      right = ["Wizyta,s:Pacjent"]

      # Contract versions retain the historical encoding; E10 documents do not
      # inherit its delimiter ambiguity.
      assert EhOsContract.Digest.canonical(left) == EhOsContract.Digest.canonical(right)
      refute EhOsContract.Digest.document_hash(left) == EhOsContract.Digest.document_hash(right)
    end

    test "remain independent of map insertion order" do
      assert EhOsContract.Digest.document_hash(%{"b" => 1, "a" => 2}) ==
               EhOsContract.Digest.document_hash(%{"a" => 2, "b" => 1})
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
