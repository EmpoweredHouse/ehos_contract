defmodule PNS.DeploymentTest do
  @moduledoc """
  Stage 1.6: **the contract version as a first-class answer.**

  The acceptance criterion has three parts and the sharpest is the last: the report
  says which paths are new, which disappeared, which events come from an earlier
  version — and **without a single false drift**.

  The first block below reproduces the false drift that used to be here, so that
  the fix does not turn out to be a fix for something that never happened.
  """

  use Taxvision.DataCase, async: false

  alias Taxvision.Contracts.AccountingMonth, as: Contract

  @period "2026-07"

  defp open_month(company) do
    {:ok, _} = Taxvision.Api.open_month(accountant(company), %{company_id: company, period: @period})
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

      assert {:registry_data_consistent, :monthly_tasks_generated} in edges
      assert Contract.version() == before, "the contract did not change"

      # So: if somebody removed the handler, the `contract_version` in the log
      # would stay the same and the edge would stop being declared.
    end

    test "an edge declared in a recorded deployment is history, not drift" do
      open_month("c-1")

      # A deployment in which this edge **was** declared, and which is not in the
      # registry today — exactly the situation after removing a handler.
      deployment(%{wiring_version: "wiring-1", edges: ["accounting_month_opened->month_closed"]})

      Repo.insert!(%PNS.Event{
        type: "month_closed",
        contract: inspect(Contract),
        contract_version: Contract.version(),
        process: "accounting_month",
        instance_id: "accounting_month|c-1|#{@period}",
        correlation_id: Ecto.UUID.generate(),
        causation_id: List.first(events_of(:accounting_month_opened)).id,
        payload: %{},
        occurred_at: DateTime.utc_now()
      })

      entry =
        PNS.Graph.overlay()
        |> Enum.find(&(&1.from == "accounting_month_opened" and &1.to == "month_closed"))

      assert entry.state == :historical,
             "the edge was declared when it ran — blaming it for drift is the false " <>
               "alarm criterion 1.6 forbids"
    end

    test "an edge that was never declared is still drift" do
      # The fix has no business silencing real drift.
      open_month("c-1")

      Repo.insert!(%PNS.Event{
        type: "never_declared",
        contract: inspect(Contract),
        contract_version: Contract.version(),
        correlation_id: Ecto.UUID.generate(),
        causation_id: List.first(events_of(:accounting_month_opened)).id,
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
      assert "registry_data_consistent->monthly_tasks_generated" in deployed.edges
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
      open_month("c-1")

      report = PNS.Deployment.report(Contract)
      first = List.first(events_of(:data_completeness_confirmed))

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
      open_month("c-1")

      Repo.insert!(%PNS.Event{
        type: "data_completeness_confirmed",
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
