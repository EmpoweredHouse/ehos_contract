defmodule PNS.DeploymentTest do
  @moduledoc """
  Stage 1.6: **the contract version as a first-class answer.**

  The acceptance criterion has three parts and the sharpest is the last: the report
  says which paths are new, which disappeared, which events come from an earlier
  version — and **without a single false drift**.

  The first block below reproduces the false drift that used to be here, so that
  the fix does not turn out to be a fix for something that never happened.
  """

  use PNS.DataCase, async: false

  alias ProcessShapes.Rig, as: Contract

  # One run, driven all the way to its terminal event: `item_received` pairs the
  # item and closes the case. Three events and two edges, which is everything this
  # file needs a run for.
  defp a_run(case_id) do
    PNS.emit!(Contract, :item_received, %{case_id: case_id, item_no: 1, amount: 100})
  end

  defp deployment(attrs) do
    Repo.insert!(
      struct(
        %PNS.Deployment{
          contract: inspect(Contract),
          contract_version: Contract.version(),
          wiring_version: "wiring-old",
          events: Contract.event_names() |> Enum.map(&to_string/1) |> Enum.sort(),
          edges: [],
          first_seen_at: DateTime.utc_now()
        },
        attrs
      )
    )
  end

  describe "the false drift the acceptance criterion forbids" do
    test "removing a handler changes no version — and yet changes the graph" do
      # This is the cause, not the symptom. `version/0` hashes the contract's
      # declarations; paths come from handlers' `publishes:`, which is not in that
      # hash.
      before = Contract.version()
      edges = PNS.Registry.edges() |> Enum.map(&{&1.from, &1.to})

      assert {:item_received, :item_paired} in edges
      assert Contract.version() == before, "the contract did not change"

      # So: if somebody removed the handler, the `contract_version` in the log
      # would stay the same and the edge would stop being declared.
    end

    test "an edge declared in a recorded deployment is history, not drift" do
      a_run("c-1")

      # A deployment in which this edge **was** declared, and which is not in the
      # registry today — exactly the situation after removing a handler. Nothing
      # subscribes to `case_closed` now, so this path exists only in history.
      deployment(%{wiring_version: "wiring-1", edges: ["case_closed->item_appealed"]})

      Repo.insert!(%PNS.Event{
        type: "item_appealed",
        contract: inspect(Contract),
        contract_version: Contract.version(),
        process: "pairing",
        instance_id: "pairing|c-1",
        correlation_id: Ecto.UUID.generate(),
        causation_id: List.first(events_of(:case_closed)).id,
        payload: %{},
        occurred_at: DateTime.utc_now()
      })

      entry =
        PNS.Graph.overlay()
        |> Enum.find(&(&1.from == "case_closed" and &1.to == "item_appealed"))

      assert entry.state == :historical,
             "the edge was declared when it ran — blaming it for drift is the false " <>
               "alarm criterion 1.6 forbids"
    end

    test "an edge that was never declared is still drift" do
      # The fix has no business silencing real drift.
      a_run("c-1")

      Repo.insert!(%PNS.Event{
        type: "never_declared",
        contract: inspect(Contract),
        contract_version: Contract.version(),
        correlation_id: Ecto.UUID.generate(),
        causation_id: List.first(events_of(:case_closed)).id,
        payload: %{},
        occurred_at: DateTime.utc_now()
      })

      entry = PNS.Graph.overlay() |> Enum.find(&(&1.to == "never_declared"))

      assert entry.state == :drift
    end
  end

  describe "two deployment identities" do
    test "the contract version and the wiring version are separate and move separately" do
      PNS.Deployment.record!()
      [deployed] = PNS.Deployment.all(Contract)

      assert deployed.contract_version == Contract.version()
      assert deployed.wiring_version != deployed.contract_version

      # The wiring knows the paths, the contract does not.
      assert "item_received->item_paired" in deployed.edges
      refute Enum.empty?(deployed.events)
    end

    test "the same code recorded twice is one deployment" do
      PNS.Deployment.record!()
      PNS.Deployment.record!()

      assert length(PNS.Deployment.all(Contract)) == 1
    end

    test "the wiring hash is canonical — from sorted strings, not from a term" do
      # `version/0` hashes through `term_to_binary`, so an OTP upgrade could
      # reclassify the whole history (gap 2.4). That problem does not exist here,
      # and this is the model for that fix.
      PNS.Deployment.record!()
      [a] = PNS.Deployment.all(Contract)

      Repo.delete_all(PNS.Deployment)
      PNS.Deployment.record!()
      [b] = PNS.Deployment.all(Contract)

      assert a.wiring_version == b.wiring_version
    end
  end

  describe "the report: what is deployed, since when, what changed" do
    test "since when is the first event under this version, not the deploy moment" do
      PNS.Deployment.record!()
      a_run("c-1")

      report = PNS.Deployment.report(Contract)
      first = List.first(events_of(:item_received))

      assert report.deployed.contract_version == Contract.version()
      assert report.deployed.since == first.occurred_at
    end

    test "a deployment that has emitted nothing has `since: nil`" do
      # Deployed and unproven. `nil` is more honest here than a deploy date the
      # engine does not know.
      PNS.Deployment.record!()

      assert PNS.Deployment.report(Contract).deployed.since == nil
    end

    test "versions in the log with counts and ranges" do
      a_run("c-1")

      Repo.insert!(%PNS.Event{
        type: "item_received",
        contract: inspect(Contract),
        contract_version: "old-version",
        correlation_id: Ecto.UUID.generate(),
        payload: %{},
        occurred_at: ~U[2026-06-01 09:00:00.000000Z]
      })

      report = PNS.Deployment.report(Contract)
      versions = Map.new(report.in_log, &{&1.contract_version, &1})

      assert versions["old-version"].events == 1
      assert versions["old-version"].first_at == ~U[2026-06-01 09:00:00.000000Z]
      assert versions[Contract.version()].events > 1

      # How many events come from a version other than the deployed one — stated
      # outright, without the reader having to work it out.
      assert report.from_earlier_versions == 1
    end

    test "the diff speaks separately about events and about paths" do
      # They move independently: a handler can add a path without the contract
      # changing.
      deployment(%{
        wiring_version: "wiring-1",
        events: ["a", "b"],
        edges: ["a->b"],
        first_seen_at: ~U[2026-08-01 09:00:00.000000Z]
      })

      deployment(%{
        contract_version: "new",
        wiring_version: "wiring-2",
        events: ["a", "c"],
        edges: ["a->b", "a->c"],
        first_seen_at: ~U[2026-08-02 09:00:00.000000Z]
      })

      change = PNS.Deployment.report(Contract).changed

      assert change.events_added == ["c"]
      assert change.events_removed == ["b"]
      assert change.paths_added == ["a->c"]
      assert change.paths_removed == []
    end

    test "one deployment is no change, not an empty change" do
      PNS.Deployment.record!()
      assert PNS.Deployment.report(Contract).changed == nil
    end
  end
end
