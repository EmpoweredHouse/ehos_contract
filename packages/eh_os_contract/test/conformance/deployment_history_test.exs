defmodule EhOsContract.DeploymentHistoryTest do
  @moduledoc """
  The deployment table's history for a v2 contract: **one row per wiring that booted,
  and what moved between two of them.**

  `deployment_test.exs` pins what a v2 row holds — its steps as paths, its wiring,
  a promise's digest being its rule. This file pins the mechanism around the row, which
  the fourth question of the report rests on: recording is idempotent, a row written
  before the digests column is repaired rather than left blind, the diff between the
  last two rows speaks separately about events, paths and declarations, and the date a
  declaration last moved is drawn only where it really moved.

  The sharpest of these is the one events and paths cannot show. A promise whose
  window moved adds and removes nothing, so a diff of names and edges reports a change
  to the agreement as four empty lists — and a report reading that says nothing
  changed on the day the rule did.
  """

  use EhOsContract.DataCase, async: false

  alias EhOsContract.{Conformance, Deployment, Model, Report}
  alias ProcessShapes.{Handling, Promised, Seed}

  @promise_key "promise:completed_or_refusal_notified"

  defp version, do: Model.fetch(Promised).version

  # The model digests the process as a whole; the deployment adds a digest of each
  # promise's rule, so a changed promise has a boundary of its own. The promise is a
  # process module's since plan DD, P2g (#228), recorded in the module's own row.
  defp digests do
    [promise] = Model.process(Handling).promises
    Map.put(Model.fetch(Handling).digests, @promise_key, Deployment.promise_digest(promise))
  end

  defp deployment(attrs) do
    Repo.insert!(
      struct(
        %Deployment{
          contract: EhOsContract.Model.fetch(Promised).id,
          contract_version: version(),
          wiring_version: "wiring-old",
          events: Model.fetch(Promised).events |> Enum.map(&to_string(&1.name)) |> Enum.sort(),
          edges: [],
          first_seen_at: DateTime.utc_now()
        },
        attrs
      )
    )
  end

  describe "recording" do
    test "the same code recorded twice is one deployment" do
      Deployment.record!()
      Deployment.record!()

      assert length(Deployment.all(Promised)) == 1
    end

    test "the row carries one digest per declaration, and one per promise, so a change is attributable" do
      Deployment.record!()
      [deployed] = Deployment.all(Handling)

      # String keys on both sides: the column is jsonb, and the digests are computed
      # with string keys for that reason rather than leaving the round trip to surprise
      # somebody.
      assert deployed.declaration_digests == digests()
      assert deployed.declaration_digests["process"]
      assert [%{declaration_digests: contract}] = Deployment.all(Promised)
      assert contract == Model.fetch(Promised).digests
    end

    test "a row recorded before the column existed is backfilled on the next boot" do
      # The one case `on_conflict: :nothing` got wrong: the first boot after the
      # migration meets a row written before it, and leaving that row null would make
      # the whole mechanism blind for the version that is actually deployed.
      Deployment.record!()
      Repo.update_all(Deployment, set: [declaration_digests: nil])

      Deployment.record!()
      [deployed] = Deployment.all(Handling)

      assert deployed.declaration_digests == digests()
      assert length(Deployment.all(Handling)) == 1
    end

    test "the wiring hash is canonical, the same on every boot of the same code" do
      Deployment.record!()
      [a] = Deployment.all(Promised)

      Repo.delete_all(Deployment)
      Deployment.record!()
      [b] = Deployment.all(Promised)

      assert a.wiring_version == b.wiring_version
    end
  end

  describe "the report: what is deployed, since when, what changed" do
    test "a deployment that has emitted nothing has `since: nil`" do
      # Deployed and unproven. `nil` is more honest here than a deploy date the engine
      # does not know.
      Deployment.record!()

      assert Deployment.report(Promised).deployed.since == nil
    end

    test "versions in the log with counts and ranges" do
      Seed.deploy()
      Seed.request("r-1", :request_approved)

      record_event!(%{
        type: "process_shapes.promised.request_received",
        contract: EhOsContract.Model.fetch(Promised).id,
        contract_version: "old-version",
        runs: [{"process_shapes.handling", "process_shapes.handling|r-0"}],
        payload: %{"request_id" => "r-0"},
        occurred_at: ~U[2026-06-01 09:00:00.000000Z]
      })

      report = Deployment.report(Promised)
      versions = Map.new(report.in_log, &{&1.contract_version, &1})

      assert versions["old-version"].events == 1
      assert versions["old-version"].first_at == ~U[2026-06-01 09:00:00.000000Z]
      assert versions[version()].events > 1

      # How many events come from a version other than the deployed one — stated
      # outright, without the reader having to work it out.
      assert report.from_earlier_versions == 1
    end

    test "the diff speaks separately about events and about paths" do
      deployment(%{
        wiring_version: "wiring-1",
        events: ["a", "b"],
        edges: ["event:a->command:b"],
        first_seen_at: ~U[2026-08-01 09:00:00.000000Z]
      })

      deployment(%{
        contract_version: "new",
        wiring_version: "wiring-2",
        events: ["a", "c"],
        edges: ["event:a->command:b", "event:a->command:c"],
        first_seen_at: ~U[2026-08-02 09:00:00.000000Z]
      })

      change = Deployment.report(Promised).changed

      assert change.events_added == ["c"]
      assert change.events_removed == ["b"]
      assert change.paths_added == ["event:a->command:c"]
      assert change.paths_removed == []
    end

    test "one deployment is no change, not an empty change" do
      Deployment.record!()
      assert Deployment.report(Promised).changed == nil
    end
  end

  describe "a change events and paths cannot show" do
    # Two deployments identical in everything the diff could see before: same event
    # names, same steps. Only the promise's window moved — which is the whole class of
    # change this exists for.
    defp two_versions_differing_only_in(digests_old, digests_new) do
      deployment(%{
        wiring_version: "wiring-1",
        events: ["a", "b"],
        edges: ["event:a->command:b"],
        declaration_digests: digests_old,
        first_seen_at: ~U[2026-08-01 09:00:00.000000Z]
      })

      deployment(%{
        contract_version: "new",
        wiring_version: "wiring-2",
        events: ["a", "b"],
        edges: ["event:a->command:b"],
        declaration_digests: digests_new,
        first_seen_at: ~U[2026-08-02 09:00:00.000000Z]
      })

      Deployment.report(Promised).changed
    end

    test "a changed promise window is named, with events and paths still empty" do
      change =
        two_versions_differing_only_in(
          %{@promise_key => "aaaaaaaaaaaa", "event:request_received" => "cccccccccccc"},
          %{@promise_key => "bbbbbbbbbbbb", "event:request_received" => "cccccccccccc"}
        )

      assert change.declarations.changed == [@promise_key]
      assert change.declarations.added == []
      assert change.declarations.removed == []

      # The control, and the reason this test exists: before this key, the same edit
      # produced exactly these four empty lists and nothing else.
      assert change.events_added == []
      assert change.events_removed == []
      assert change.paths_added == []
      assert change.paths_removed == []
    end

    test "a new declaration is a birth, not a change" do
      change =
        two_versions_differing_only_in(
          %{"event:request_received" => "cccccccccccc"},
          %{
            "event:request_received" => "cccccccccccc",
            "command:withdraw_request" => "dddddddddddd"
          }
        )

      assert change.declarations.added == ["command:withdraw_request"]
      assert change.declarations.changed == []
    end

    test "a row from before the column says so, rather than saying nothing moved" do
      change = two_versions_differing_only_in(nil, %{"event:request_received" => "cccccccccccc"})

      assert change.declarations == :not_recorded
    end

    test "the report says it cannot compare, not that nothing changed" do
      two_versions_differing_only_in(nil, %{"event:request_received" => "cccccccccccc"})

      text = Promised |> Conformance.report() |> Report.render()

      assert text =~ "was not recorded, so it cannot be compared"
      refute text =~ "Declarations changed:"
    end

    test "the report names the changed declaration" do
      two_versions_differing_only_in(
        %{@promise_key => "aaaaaaaaaaaa"},
        %{@promise_key => "bbbbbbbbbbbb"}
      )

      text = Promised |> Conformance.report() |> Report.render()

      assert text =~ "Declarations changed: 1 (#{@promise_key})"
    end
  end

  describe "when a declaration last moved" do
    test "a later change overwrites an earlier one" do
      # The value is the *last* time the rule moved. A run before an older change is
      # also before the newer one, so the newest boundary is the only one that can be
      # applied without claiming more than the two buckets support.
      for {digest, at} <- [
            {"aaaaaaaaaaaa", ~U[2026-08-01 09:00:00.000000Z]},
            {"bbbbbbbbbbbb", ~U[2026-08-05 09:00:00.000000Z]},
            {"cccccccccccc", ~U[2026-08-09 09:00:00.000000Z]}
          ] do
        deployment(%{
          wiring_version: "w-#{digest}",
          declaration_digests: %{@promise_key => digest},
          first_seen_at: at
        })
      end

      assert Deployment.declaration_boundaries(Promised) ==
               %{@promise_key => ~U[2026-08-09 09:00:00.000000Z]}
    end

    test "the day the column arrived is not a day every declaration changed" do
      # Rows with no digests drop out before pairing. Without that, the migration date
      # would read as a change to everything at once — a false boundary on the one date
      # guaranteed to sit in the middle of everybody's history.
      deployment(%{
        wiring_version: "w1",
        declaration_digests: nil,
        first_seen_at: ~U[2026-08-01 09:00:00.000000Z]
      })

      deployment(%{
        wiring_version: "w2",
        declaration_digests: %{@promise_key => "aaaaaaaaaaaa"},
        first_seen_at: ~U[2026-08-05 09:00:00.000000Z]
      })

      assert Deployment.declaration_boundaries(Promised) == %{}
    end

    test "a declaration that never moved has no boundary" do
      deployment(%{
        wiring_version: "w1",
        declaration_digests: %{@promise_key => "aaaaaaaaaaaa"},
        first_seen_at: ~U[2026-08-01 09:00:00.000000Z]
      })

      deployment(%{
        wiring_version: "w2",
        declaration_digests: %{@promise_key => "aaaaaaaaaaaa"},
        first_seen_at: ~U[2026-08-05 09:00:00.000000Z]
      })

      assert Deployment.declaration_boundaries(Promised) == %{}
    end
  end
end
