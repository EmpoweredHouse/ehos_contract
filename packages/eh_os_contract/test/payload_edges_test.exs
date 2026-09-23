defmodule EhOsContract.PayloadEdgesTest do
  @moduledoc """
  **What the payload types accept at their edges, and what a round trip does to it.**

  `test/payload_test.exs` pins the rule — a declared field is present, and holds what
  its type names. This file pins the corners of that rule: the empty string, the very
  large integer, the timestamp written six different ways, the enum that checks almost
  nothing next to the one that now can, and the separator character inside a value that
  a separator has to survive.

  Everything here describes today's behaviour.

  The fixture is invented and stays out of the registry: it exists to carry one field
  of every type, which is not a claim about anybody's process.
  """

  use EhOsContract.DataCase, async: false

  alias EhOsContract.Payload

  defmodule Values do
    @moduledoc "# INVENTED. One field of every payload type, and nothing else."

    use EhOsContract.Contract

    event :measured,
      label: "Measured",
      payload: %{
        case_id: :id,
        note: :string,
        amount: :integer,
        at: :timestamp,
        kind: :enum,
        # A second `:enum` field, deliberately declared with a set — next to `kind`,
        # which deliberately is not — to prove the two forms coexist and that giving
        # one field a set does not force it on the other.
        severity: {:enum, [:low, :high]}
      },
      process: :values

    process :values, label: "Values", instance: [:case_id]
  end

  defmodule TwoKeyed do
    @moduledoc "# INVENTED. A run keyed by two fields, so the separator has work to do."

    use EhOsContract.Contract

    event :happened, label: "Happened", payload: %{a: :id, b: :id}, process: :two

    process :two, label: "Two", instance: [:a, :b]
  end

  @at ~U[2026-08-05 09:00:00.000000Z]

  defp payload(overrides) do
    Map.merge(
      %{case_id: "c-1", note: "a note", amount: 1, at: @at, kind: :ordinary, severity: :low},
      overrides
    )
  end

  defp emit(overrides), do: EhOsContract.emit!(Values, :measured, payload(overrides))

  defp stored(event), do: Repo.get!(EhOsContract.Event, event.id).payload

  defp round_trip(event) do
    Payload.cast(Values.event(:measured), stored(event))
  end

  describe ":string" do
    test "the empty string is accepted, where an empty :id is not" do
      # Not an inconsistency. `:string` means "text a human typed", and a human typing
      # nothing is a fact about the process worth keeping; `:id` names something, and an
      # identifier that identifies nothing is a missing value wearing a type. The two
      # types exist separately for exactly this kind of difference — the retention check
      # reads the same distinction — so collapsing either into the other loses it.
      assert emit(%{note: ""}).payload["note"] == ""

      assert_raise ArgumentError, ~r/`case_id` is declared as :id and holds ""/, fn ->
        emit(%{case_id: ""})
      end
    end

    test "whitespace, newlines and unicode survive the round trip unchanged" do
      # The log is what an evidence report quotes from. Text mangled on the way in
      # cannot be un-mangled later, and the damage is invisible until somebody who
      # speaks the language reads the report.
      text = "  zażółć\ngęślą jaźń\t— ✓  "

      assert round_trip(emit(%{note: text})).note == text
    end
  end

  describe ":integer" do
    test "negative is accepted" do
      # Nothing in the engine reads a payload value, so there is no arithmetic here to
      # protect — but a client counting a correction or a reversal has no other type to
      # reach for, and a refusal would push them into `:string`, which is the one type
      # that triggers the retention check.
      assert round_trip(emit(%{amount: -1})).amount == -1
    end

    test "an integer far beyond 64 bits survives the round trip through the log" do
      # The BEAM has bignums and the column is JSON, so nothing truncates on the way in.
      # Worth pinning because the failure mode if it ever did would be silent: a number
      # that is merely wrong, in a field the engine never looks at, discovered by whoever
      # sums the column months later.
      huge = 12_345_678_901_234_567_890_123_456_789

      assert round_trip(emit(%{amount: huge})).amount == huge
    end

    test "zero is a value and not an absence" do
      assert round_trip(emit(%{amount: 0})).amount == 0
    end
  end

  describe ":timestamp" do
    test "an offset is normalised to UTC, and the offset itself is not kept" do
      # The log is in UTC and `EhOsContract.Duration` shifts in seconds, so an assertion window
      # cannot be evaluated against a local time. What is lost is the offset: after this,
      # nothing in the log says the fact happened at 11 in Warsaw. If a client ever needs
      # that, it is a declared field of its own, not a property recoverable later.
      cast = Payload.cast(Values.event(:measured), %{"at" => "2026-08-05T11:00:00+02:00"})

      assert cast.at == ~U[2026-08-05 09:00:00Z]
    end

    test "microsecond precision is preserved exactly as given, in both directions" do
      # `DateTime.compare/2` treats these as the same instant and `==` does not, so a
      # comparison written with `==` would behave differently for two timestamps that
      # describe the same moment. The evaluator uses `compare` throughout; this test is
      # what notices if that ever stops being true.
      with_micro = ~U[2026-08-05 09:00:00.123456Z]
      without = ~U[2026-08-05 09:00:00Z]

      assert round_trip(emit(%{at: with_micro})).at == with_micro
      assert round_trip(emit(%{at: without})).at == without

      # The same instant, and not the same term.
      assert DateTime.compare(without, ~U[2026-08-05 09:00:00.000000Z]) == :eq
      refute without == ~U[2026-08-05 09:00:00.000000Z]
    end

    test "before 1970 and far into the future both survive" do
      # A process that records a date of birth or a statutory retention horizon puts both
      # of these in a payload on its first day. Unix-epoch arithmetic anywhere in the path
      # would break the first and overflow the second, and neither would raise.
      moon = ~U[1969-07-20 20:17:00.000000Z]
      far = ~U[9999-12-31 23:59:59.000000Z]

      assert round_trip(emit(%{at: moon})).at == moon
      assert round_trip(emit(%{at: far})).at == far
    end

    test "text that is not a timestamp is left alone rather than repaired, and then refused" do
      # `cast/2` repairs what JSON destroys and coerces nothing, so an unparseable string
      # stays a string and validation is what rejects it. If cast silently produced a
      # `nil` or a default here, the refusal would become an acceptance of the wrong
      # moment.
      assert_raise ArgumentError, ~r/`at` is declared as :timestamp/, fn ->
        emit(%{at: "the fifth of August"})
      end
    end
  end

  describe ":enum" do
    test "bare :enum accepts any atom and any string, deliberately, still" do
      # Fixed 21 August 2026: `{:enum, [...]}` now lets a field declare its set —
      # `severity` below does exactly that. `kind` here stays bare on purpose,
      # proving the fix is opt-in: a field that never asked for a set keeps
      # accepting any name, and giving one field a set does not retroactively
      # tighten its neighbour.
      assert round_trip(emit(%{kind: :not_a_real_kind})).kind == "not_a_real_kind"
      assert round_trip(emit(%{kind: "anything at all"})).kind == "anything at all"
    end

    test "and refuses what is not a name at all" do
      # The control. The type is weak, not absent.
      assert_raise ArgumentError, ~r/`kind` is declared as :enum/, fn -> emit(%{kind: 3}) end
    end

    test "an atom comes back as a string, so it does not survive as an atom" do
      # JSON has no atoms, and `cast/2` restores only `:timestamp` — deliberately, since
      # rebuilding atoms from a log would ask the atom table to vouch for names that may
      # have been deleted. So a handler on the asynchronous side sees `"ordinary"` where
      # the synchronous one saw `:ordinary`, and a `case` on atoms silently stops
      # matching after a handler is made async.
      assert round_trip(emit(%{kind: :ordinary})).kind == "ordinary"
    end
  end

  describe "{:enum, [...]} — a declared set, fixed 21 August 2026" do
    test "a member of the declared set is accepted, as an atom or as a string" do
      assert round_trip(emit(%{severity: :high})).severity == "high"
      assert round_trip(emit(%{severity: "high"})).severity == "high"
    end

    test "anything outside the declared set is refused, unlike bare :enum" do
      assert_raise ArgumentError, ~r/`severity` is declared as {:enum, \[:low, :high\]}/, fn ->
        emit(%{severity: :medium})
      end
    end

    test "a name-shaped value that just is not a member is still refused" do
      # The distinction from "not a name at all" (:enum's own control, above): this
      # is a legal name, spelled correctly, that simply is not one of the two the
      # contract named.
      assert_raise ArgumentError, ~r/holds "medium"/, fn -> emit(%{severity: "medium"}) end
    end
  end

  describe "string keys after a JSON round trip" do
    test "a payload supplied entirely with string keys is accepted and keyed correctly" do
      # This is the shape an asynchronous handler re-emitting from job arguments produces.
      # `cast/2` runs before validation and before run identity is computed, so a string
      # key is not a second class of payload — if it were, the same emission would be
      # legal on one dispatch path and refused on the other.
      event =
        EhOsContract.emit!(Values, :measured, %{
          "case_id" => "c-9",
          "note" => "text",
          "amount" => 3,
          "at" => "2026-08-05T09:00:00Z",
          "kind" => "ordinary",
          "severity" => "low"
        })

      assert event.instance_id == "values|c-9"
      assert round_trip(event).at == ~U[2026-08-05 09:00:00Z]
    end
  end

  describe "the separator inside a run identity value" do
    test "unicode passes through untouched" do
      assert EhOsContract.emit!(Values, :measured, payload(%{case_id: "żółw-✓"})).instance_id ==
               "values|żółw-✓"
    end

    test "a separator in a value does not merge two different runs" do
      # The reason the escaping exists. Without it `("x|y", "z")` and `("x", "y|z")` are
      # one run key, so two companies' events land in one run: an assertion is counted
      # across both, and the coverage denominator counts them as one.
      a = EhOsContract.emit!(TwoKeyed, :happened, %{a: "x|y", b: "z"})
      b = EhOsContract.emit!(TwoKeyed, :happened, %{a: "x", b: "y|z"})

      refute a.instance_id == b.instance_id
      assert a.instance_id =~ "%7C"
    end

    test "a value containing the escape sequence itself does not collide with one containing the separator" do
      # Found while writing this file, and not on the list it was written from. The
      # escaping now replaces `%` with `%25` before it replaces `|` with `%7C`, so a
      # value that literally contains the text `%7C` no longer produces the same run
      # key as a value that contains `|`. `EhOsContract.Job` gets the same fix, for the same
      # reason: its idempotency key uses the same escaping on purpose.
      literal = EhOsContract.Instance.key(TwoKeyed, :happened, %{a: "x%7Cy", b: "z"})
      separator = EhOsContract.Instance.key(TwoKeyed, :happened, %{a: "x|y", b: "z"})

      refute literal == separator
    end
  end
end
