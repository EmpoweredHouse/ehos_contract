defmodule EhOsContract.Conformance.WireReportTest do
  @moduledoc """
  A v2 contract's report **as values that survive a wire** (`conformance.v3`).

  The structural walk below is the point of this file. It does not assert on any
  particular key, so it covers the ones a later stage adds — and the v2 report already
  carries keys v1 never had: steps as
  `%{kind, name, label}`, waiting and failing split by source, the wiring, the
  scenarios. A test naming the keys it knows about would pass while the next one
  arrived carrying a tuple or a `DateTime` struct, and `Jason` refuses a tuple outright.

  Each contract is walked in a state that puts something in the keys most likely to
  carry such a value: a promise whose declaration moved (a `DateTime`), a confirmed
  deadline (a duration), a rig with scenarios and a process manager.

  Since plan DD, P2g (#228) the promise and the deadline are process modules',
  `ProcessShapes.Handling` and `ProcessShapes.Timing`, which the wire does not carry
  yet (#213): their reports are walked through the same projection,
  `EhOsContract.Conformance.Wire.encode/1`, which `as_data/2` puts a contract's
  through.
  """

  use EhOsContract.DataCase, async: false

  alias EhOsContract.{Conformance, Deployment}
  alias EhOsContract.Conformance.Wire
  alias ProcessShapes.{Handling, Promised, Seed}

  @clerk EhOsContract.Actor.credential("u-1", ["dispatch_rig.open_account"])

  defp leaves(map) when is_map(map),
    do: Enum.flat_map(map, fn {k, v} -> [{:key, k} | leaves(v)] end)

  defp leaves(list) when is_list(list), do: Enum.flat_map(list, &leaves/1)
  defp leaves(other), do: [{:value, other}]

  defp assert_json_only(data) do
    for {kind, term} <- leaves(data) do
      case kind do
        :key ->
          assert is_binary(term), "map key #{inspect(term)} is not a string"

        :value ->
          assert is_binary(term) or is_number(term) or is_boolean(term) or is_nil(term),
                 "value #{inspect(term)} is #{typeof(term)}, which JSON has no shape for"
      end
    end

    # The walk above states the rule; this states that the rule was the right one.
    assert {:ok, _json} = Jason.encode(data)
  end

  # A refusal, so a step waits and the promise has a verdict; and the deployed row
  # beside an earlier one whose promise said something else, so the promise carries
  # the date its declaration last moved.
  defp promised_with_history do
    Seed.deploy()
    Seed.request("r-1", :request_refused)

    Repo.insert!(%Deployment{
      contract: "process:process_shapes.handling",
      contract_version: Handling.__eh_os_contract_model__().version,
      wiring_version: "wiring-earlier",
      events: [],
      edges: [],
      declaration_digests: %{"promise:completed_or_refusal_notified" => "aaaaaaaaaaaa"},
      first_seen_at: ~U[2026-08-01 09:00:00.000000Z]
    })

    Deployment.record!()
  end

  describe "the projection leaves nothing JSON cannot carry" do
    test "for request handling, with a step waiting and a promise that changed" do
      promised_with_history()

      data =
        Conformance.as_data(Promised,
          since: ~U[2026-01-01 00:00:00.000000Z],
          until: ~U[2027-01-01 00:00:00.000000Z]
        )

      assert_json_only(data)

      process =
        Handling
        |> Conformance.report(
          since: ~U[2026-01-01 00:00:00.000000Z],
          until: ~U[2027-01-01 00:00:00.000000Z]
        )
        |> Wire.encode()

      assert_json_only(process)

      # The control: the state above did reach the keys it was set up for, so the walk
      # met a `DateTime` and a waiting step rather than a report with nothing in it.
      [p] = process["processes"]
      [promise] = p["promises"]
      assert {:ok, _, _} = DateTime.from_iso8601(promise["declaration_changed_at"])
      assert [_waiting] = data["report"]["paths"]["in_flight"]
    end

    test "for a timed run, whose confirmed deadline is measured" do
      Seed.deploy()
      Seed.start_run("r-1", ~U[2026-09-01 09:00:00.000000Z])

      data = Conformance.as_data(ProcessShapes.Timed, now: ~U[2026-09-01 12:00:00.000000Z])

      assert_json_only(data)

      process =
        ProcessShapes.Timing
        |> Conformance.report(now: ~U[2026-09-01 12:00:00.000000Z])
        |> Wire.encode()

      assert_json_only(process)

      [p] = process["processes"]
      assert p["duration"]["deadline"] == %{"count" => 1, "unit" => "hour"}
    end

    test "for a rig with scenarios and a process manager" do
      EhOsContract.Testing.drain()

      {:ok, _} =
        EhOsContract.dispatch(
          DispatchRig.Ledger,
          %DispatchRig.Ledger.Commands.OpenAccount{account_id: "a-1", branch_id: "b-7"},
          actor: @clerk
        )

      data = Conformance.as_data(DispatchRig.Ledger)

      assert_json_only(data)
      assert data["report"]["scenarios"] != nil
    end
  end

  describe "the values a consumer joins on" do
    setup do: promised_with_history()

    test "a contract reads as its id, as in the log, with its module beside it" do
      # Plan DD, P1a (#183): every row of the log names a contract by its id (ID4,
      # #178), so a consumer joining the two does not have to know that one side
      # spells it differently. The module is the code's name, for a reader of it.
      report = Conformance.as_data(Promised)["report"]

      assert report["contract"] == "process_shapes.promised"
      assert report["module"] == "ProcessShapes.Promised"
      assert report["deployment"]["contract"] == "process_shapes.promised"
    end

    test "a duration is named, not positional" do
      [p] = Handling |> Conformance.report() |> Wire.encode() |> Map.fetch!("processes")
      [promise] = p["promises"]

      assert promise["within"] == %{"count" => 2, "unit" => "day"}
    end

    test "the envelope says when, and the report which engine" do
      data = Conformance.as_data(Promised)

      assert {:ok, _, _} = DateTime.from_iso8601(data["generated_at"])
      # The engine version lives in the report and is deliberately not repeated in
      # the envelope: two copies of one fact are two things to drift apart.
      assert data["report"]["engine"] == EhOsContract.version()
      refute Map.has_key?(data, "engine")
    end
  end

  defp typeof(term) when is_tuple(term), do: "a tuple"
  defp typeof(term) when is_atom(term), do: "an atom"
  defp typeof(term) when is_struct(term), do: "a struct"
  defp typeof(_), do: "something else"
end
