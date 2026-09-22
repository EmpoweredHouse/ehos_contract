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

    test "the row carries one digest per declaration, so a change is attributable" do
      PNS.Deployment.record!()
      [deployed] = PNS.Deployment.all(Contract)

      # String keys on both sides: the column is jsonb, and the contract computes
      # string keys for that reason rather than leaving the round trip to surprise
      # somebody.
      assert deployed.declaration_digests == Contract.declaration_digests()
      assert deployed.declaration_digests["process:pairing"]
    end

    test "a row recorded before the column existed is backfilled on the next boot" do
      # The one case `on_conflict: :nothing` got wrong, and the reason it is now
      # `{:replace, ...}`: the first boot after the migration meets a row written
      # before it. Leaving that row null would make the whole mechanism blind for
      # the version that is actually deployed.
      PNS.Deployment.record!()
      Repo.update_all(PNS.Deployment, set: [declaration_digests: nil])

      PNS.Deployment.record!()
      [deployed] = PNS.Deployment.all(Contract)

      assert deployed.declaration_digests == Contract.declaration_digests()
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

  describe "a change events and paths cannot show" do
    # Two deployments identical in everything the diff could see before: same event
    # names, same edges. Only one assertion's window moved — which is the whole
    # class of change this exists for.
    defp two_versions_differing_only_in(digests_old, digests_new) do
      deployment(%{
        wiring_version: "wiring-1",
        events: ["a", "b"],
        edges: ["a->b"],
        declaration_digests: digests_old,
        first_seen_at: ~U[2026-08-01 09:00:00.000000Z]
      })

      deployment(%{
        contract_version: "new",
        wiring_version: "wiring-2",
        events: ["a", "b"],
        edges: ["a->b"],
        declaration_digests: digests_new,
        first_seen_at: ~U[2026-08-02 09:00:00.000000Z]
      })

      PNS.Deployment.report(Contract).changed
    end

    test "a changed assertion window is named, with events and paths still empty" do
      change =
        two_versions_differing_only_in(
          %{"trace:paired_in_time" => "aaaaaaaaaaaa", "event:a" => "cccccccccccc"},
          %{"trace:paired_in_time" => "bbbbbbbbbbbb", "event:a" => "cccccccccccc"}
        )

      assert change.declarations.changed == ["trace:paired_in_time"]
      assert change.declarations.added == []
      assert change.declarations.removed == []

      # The control, and the reason this test exists: before this key, the same
      # edit produced exactly these four empty lists and nothing else.
      assert change.events_added == []
      assert change.events_removed == []
      assert change.paths_added == []
      assert change.paths_removed == []
    end

    test "a new declaration is a birth, not a change" do
      change =
        two_versions_differing_only_in(
          %{"event:a" => "cccccccccccc"},
          %{"event:a" => "cccccccccccc", "external:registry" => "dddddddddddd"}
        )

      assert change.declarations.added == ["external:registry"]
      assert change.declarations.changed == []
    end

    test "a row from before the column says so, rather than saying nothing moved" do
      change =
        two_versions_differing_only_in(nil, %{"event:a" => "cccccccccccc"})

      assert change.declarations == :not_recorded
    end

    test "the report says it cannot compare, not that nothing changed" do
      two_versions_differing_only_in(nil, %{"event:a" => "cccccccccccc"})

      text = Contract |> PNS.Conformance.report() |> PNS.Report.render()

      assert text =~ "was not recorded, so it cannot be compared"
      refute text =~ "Declarations changed:"
    end

    test "the report names the changed declaration" do
      two_versions_differing_only_in(
        %{"trace:paired_in_time" => "aaaaaaaaaaaa"},
        %{"trace:paired_in_time" => "bbbbbbbbbbbb"}
      )

      text = Contract |> PNS.Conformance.report() |> PNS.Report.render()

      assert text =~ "Declarations changed: 1 (trace:paired_in_time)"
    end
  end

  describe "when a declaration last moved" do
    test "the boundary is the deployment that introduced the new digest" do
      deployment(%{
        wiring_version: "w1",
        declaration_digests: %{"trace:t" => "aaaaaaaaaaaa"},
        first_seen_at: ~U[2026-08-01 09:00:00.000000Z]
      })

      deployment(%{
        wiring_version: "w2",
        declaration_digests: %{"trace:t" => "bbbbbbbbbbbb"},
        first_seen_at: ~U[2026-08-05 09:00:00.000000Z]
      })

      assert PNS.Deployment.declaration_boundaries(Contract) ==
               %{"trace:t" => ~U[2026-08-05 09:00:00.000000Z]}
    end

    test "a later change overwrites an earlier one" do
      # The value is the *last* time the rule moved. A run before an older change is
      # also before the newer one, so the newest boundary is the only one that can
      # be applied without claiming more than the two buckets support.
      for {digest, at} <- [
            {"aaaaaaaaaaaa", ~U[2026-08-01 09:00:00.000000Z]},
            {"bbbbbbbbbbbb", ~U[2026-08-05 09:00:00.000000Z]},
            {"cccccccccccc", ~U[2026-08-09 09:00:00.000000Z]}
          ] do
        deployment(%{
          wiring_version: "w-#{digest}",
          declaration_digests: %{"trace:t" => digest},
          first_seen_at: at
        })
      end

      assert PNS.Deployment.declaration_boundaries(Contract) ==
               %{"trace:t" => ~U[2026-08-09 09:00:00.000000Z]}
    end

    test "the day the column arrived is not a day every declaration changed" do
      # Rows with no digests drop out before pairing. Without that, the migration
      # date would read as a change to everything at once — a false boundary on the
      # one date guaranteed to sit in the middle of everybody's history.
      deployment(%{
        wiring_version: "w1",
        declaration_digests: nil,
        first_seen_at: ~U[2026-08-01 09:00:00.000000Z]
      })

      deployment(%{
        wiring_version: "w2",
        declaration_digests: %{"trace:t" => "aaaaaaaaaaaa"},
        first_seen_at: ~U[2026-08-05 09:00:00.000000Z]
      })

      assert PNS.Deployment.declaration_boundaries(Contract) == %{}
    end

    test "a declaration that never moved has no boundary" do
      deployment(%{
        wiring_version: "w1",
        declaration_digests: %{"trace:t" => "aaaaaaaaaaaa"},
        first_seen_at: ~U[2026-08-01 09:00:00.000000Z]
      })

      deployment(%{
        wiring_version: "w2",
        declaration_digests: %{"trace:t" => "aaaaaaaaaaaa"},
        first_seen_at: ~U[2026-08-05 09:00:00.000000Z]
      })

      assert PNS.Deployment.declaration_boundaries(Contract) == %{}
    end
  end
end
