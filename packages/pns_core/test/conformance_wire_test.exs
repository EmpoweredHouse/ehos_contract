defmodule PNS.Conformance.WireTest do
  @moduledoc """
  Stage 5.8: **the report as values that survive a wire.**

  The structural walk below is the point of this file. It does not assert on any
  particular key, so it covers the ones a later stage adds — and two stages have
  already added keys to this report since it was written down. A test naming the
  keys it knows about would have passed while `duration:` and
  `declaration_changed_at:` arrived carrying tuples and `DateTime` structs.
  """

  use PNS.DataCase, async: false

  alias ProcessShapes.Promised, as: Contract

  defp leaves(map) when is_map(map), do: Enum.flat_map(map, fn {k, v} -> [{:key, k} | leaves(v)] end)
  defp leaves(list) when is_list(list), do: Enum.flat_map(list, &leaves/1)
  defp leaves(other), do: [{:value, other}]

  describe "the projection" do
    test "leaves nothing JSON cannot carry" do
      data = PNS.Conformance.as_data(Contract)

      for {kind, term} <- leaves(data) do
        case kind do
          :key ->
            assert is_binary(term), "map key #{inspect(term)} is not a string"

          :value ->
            assert is_binary(term) or is_number(term) or is_boolean(term) or is_nil(term),
                   "value #{inspect(term)} is #{typeof(term)}, which JSON has no shape for"
        end
      end
    end

    test "and Jason accepts the result" do
      # The walk above states the rule; this states that the rule was the right one.
      assert is_binary(Contract |> PNS.Conformance.as_data() |> Jason.encode!())
    end

    test "a contract module reads the same here as in the log" do
      data = PNS.Conformance.as_data(Contract)

      # `PNS.Deployment` writes `inspect(contract)` into the log's `contract`
      # column, so a consumer joining the two does not have to know that one side
      # spells it differently.
      assert data["report"]["contract"] == inspect(Contract)
    end

    test "a duration is named, not positional" do
      [process] = PNS.Conformance.as_data(Contract)["report"]["processes"]
      [assertion] = process["assertions"]

      assert assertion["within"] == %{"count" => 2, "unit" => "day"}
    end

    test "the envelope names the shape" do
      data = PNS.Conformance.as_data(Contract)

      assert data["schema"] == "pns.conformance.v1"
      assert {:ok, _, _} = DateTime.from_iso8601(data["generated_at"])
      # The engine version lives in the report and is deliberately not repeated in
      # the envelope: two copies of one fact are two things to drift apart.
      assert data["report"]["engine"] == PNS.version()
    end
  end

  describe "a shape nobody decided about" do
    test "an undecided tuple raises rather than being guessed at" do
      assert_raise ArgumentError, ~r/has no decided shape on the wire/, fn ->
        PNS.Conformance.Wire.encode(%{a: {1, 2, 3}})
      end
    end

    test "an undecided struct raises too" do
      assert_raise ArgumentError, ~r/has no decided shape on the wire/, fn ->
        PNS.Conformance.Wire.encode(%{a: %Date{year: 2026, month: 9, day: 22}})
      end
    end
  end

  defp typeof(term) when is_tuple(term), do: "a tuple"
  defp typeof(term) when is_atom(term), do: "an atom"
  defp typeof(term) when is_struct(term), do: "a struct"
  defp typeof(_), do: "something else"
end
