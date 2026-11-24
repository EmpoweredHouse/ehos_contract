defmodule EhosContract.DigestTest do
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
      assert EhosContract.Digest.canonical(%{b: 1, a: 2}) == "{a:a=n:2,a:b=n:1}"
    end

    test "keeps the order of a list, because a declaration depends on it" do
      # `instance: [:company_id, :period]` is not the same agreement as its reverse:
      # the run key is those values joined in order. Sorting here would make two
      # different run keys hash alike.
      refute EhosContract.Digest.canonical([:a, :b]) == EhosContract.Digest.canonical([:b, :a])
    end

    test "does not let values of different kinds collide" do
      assert EhosContract.Digest.canonical(:x) != EhosContract.Digest.canonical("x")
      assert EhosContract.Digest.canonical(1) != EhosContract.Digest.canonical("1")
      assert EhosContract.Digest.canonical([:a]) != EhosContract.Digest.canonical({:a})
    end

    test "canonicalises a struct rather than raising a protocol error" do
      # A struct is a map without being enumerable, so the naive implementation
      # raises `Protocol.UndefinedError` in the middle of compiling somebody's
      # contract. No declaration holds a struct today, which is exactly why this
      # would have been found late.
      assert EhosContract.Digest.canonical(%EhosContract.Meta{actor: "u-1"}) =~
               "EhosContract.Meta"
    end
  end

  describe "exported document hashes" do
    test "length-prefix strings, so delimiters cannot make different documents collide" do
      left = ["Visit", "Patient"]
      right = ["Visit,s:Patient"]

      # Contract versions retain the historical encoding; E10 documents do not
      # inherit its delimiter ambiguity.
      assert EhosContract.Digest.canonical(left) == EhosContract.Digest.canonical(right)
      refute EhosContract.Digest.document_hash(left) == EhosContract.Digest.document_hash(right)
    end

    test "remain independent of map insertion order" do
      assert EhosContract.Digest.document_hash(%{"b" => 1, "a" => 2}) ==
               EhosContract.Digest.document_hash(%{"a" => 2, "b" => 1})
    end
  end

  describe "grouped declarations" do
    test "an empty group is no group" do
      # It used to move the hash, so a kind the library added moved every contract's
      # version on the day it existed, and each kind needed a list of exceptions. Since
      # plan DD, V5 (#322) moved every version once, an empty group hashes as none.
      a = EhosContract.Digest.hash_groups(events: [%{name: :x}])
      b = EhosContract.Digest.hash_groups(events: [%{name: :x}], commands: [])

      assert a == b
    end

    test "an empty group is not the same as a group with something in it" do
      a = EhosContract.Digest.hash_groups(events: [%{name: :x}], externals: [])
      b = EhosContract.Digest.hash_groups(events: [], externals: [%{name: :x}])

      refute a == b
    end

    test "member order within a group is insignificant" do
      a = EhosContract.Digest.hash_groups(events: [%{name: :x}, %{name: :y}])
      b = EhosContract.Digest.hash_groups(events: [%{name: :y}, %{name: :x}])

      assert a == b
    end
  end

  describe "the agreement and its words" do
    @event %{
      name: :visit_completed,
      label: "Visit completed",
      source: "W1 00:12:40",
      fields: [%{name: :room, type: :string, label: "Room", default: %{label: "2"}}]
    }

    test "the agreement leaves every word out, at any depth, and keeps data whole" do
      assert EhosContract.Digest.agreement(@event) == %{
               name: :visit_completed,
               fields: [%{name: :room, type: :string, default: %{label: "2"}}]
             }
    end

    test "the words keep what the agreement leaves out, and whose it is" do
      assert EhosContract.Digest.words(@event) == %{
               name: :visit_completed,
               label: "Visit completed",
               source: "W1 00:12:40",
               fields: [%{name: :room, label: "Room"}]
             }

      assert EhosContract.Digest.words(%{name: :x, type: :string, label: nil}) == nil
    end

    test "a struct is a value, not a declaration to walk" do
      assert EhosContract.Digest.agreement(%{satisfied_by: [~D[2026-01-01]], on: ~D[2026-01-02]}) ==
               %{satisfied_by: [~D[2026-01-01]], on: ~D[2026-01-02]}

      assert EhosContract.Digest.words(%{name: :x, on: ~D[2026-01-02]}) == nil
    end

    test "a scenario's words are its description, and its data is the agreement's" do
      scenario = %{
        description: "the front desk completes a visit",
        given: [%{data: %{label: "a"}}]
      }

      assert EhosContract.Digest.words(:scenarios, scenario) ==
               %{description: "the front desk completes a visit"}

      assert EhosContract.Digest.agreement(:scenarios, scenario) ==
               %{given: [%{data: %{label: "a"}}]}
    end
  end
end
