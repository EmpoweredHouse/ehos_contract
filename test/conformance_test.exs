defmodule PNS.ConformanceTest do
  @moduledoc """
  Stage 1.4: **behavioural path verification, per run.**

  The acceptance criterion is sharp and is the first block below: with 50 runs,
  none of which entered the blocking branch, the report shows **one** untraversed
  path. With one run in that branch — **none**.

  This is also the test of whether the declared-versus-observed difference is
  signal or noise — the ADR's falsification condition. Fifty runs, one line of
  report. If the report showed fifty or three, the answer would be "noise".

  The volume is simulated, but **the process is not**: the runs go through the
  existing contract from the TaxVision workshop rather than through stages added
  for this test. A contract designed against its own acceptance criterion will
  always meet it.
  """

  use Taxvision.DataCase, async: false
  use Oban.Testing, repo: Taxvision.Repo

  @divergent %{legal_form: "JDG", vat_status: "wykreślony", vies_status: "aktywny"}
  @blocking_path {:registry_discrepancy_detected, :discrepancy_notification_sent}

  defp registries(responses) do
    Application.put_env(:pns_prototype, Taxvision.Adapters.RegistryLookup.Fake, responses: responses)
    on_exit(fn -> Application.delete_env(:pns_prototype, Taxvision.Adapters.RegistryLookup.Fake) end)
  end

  defp open_month(company) do
    {:ok, _} = Taxvision.Api.open_month(accountant(company), %{company_id: company, period: "2026-07"})
  end

  defp report do
    [r] = PNS.Conformance.untraversed_paths() |> Enum.filter(&(&1.process == :accounting_month))
    r
  end

  defp paths(report), do: Enum.map(report.untraversed, &{&1.from, &1.to})

  describe "acceptance criterion" do
    test "50 runs, none in the blocking branch — exactly one untraversed path" do
      for n <- 1..50, do: open_month("c-#{n}")

      r = report()

      assert r.instances == 50
      assert r.basis == :runs
      assert paths(r) == [@blocking_path]

      # The point: the report has **one** line, not fifty and not three. If it
      # counted per event type, this one path would still come out — but with 49
      # consistent runs and one divergence (the test below) it would not.
      assert length(r.untraversed) == 1
    end

    test "one run through the blocking branch — no untraversed paths" do
      registries(%{"c-50" => {:ok, @divergent}})

      for n <- 1..50, do: open_month("c-#{n}")
      # The notification goes through an asynchronous handler, so the path only
      # closes once the job has run.
      Oban.drain_queue(queue: :events)

      r = report()

      assert r.instances == 50
      assert r.untraversed == []
      assert r.in_flight == []
    end
  end

  describe "two situations where the report easily lies" do
    test "zero runs is no basis, not three findings" do
      r = report()

      assert r.instances == 0
      assert r.basis == :no_runs

      assert r.untraversed == [],
             "a process that never started has every path untraversed — listing them " <>
               "turns \"no data\" into \"we have three problems\""

      assert r.paths == 3
    end

    test "a job waiting in the queue is not an untraversed path" do
      registries(%{"c-1" => {:ok, @divergent}})
      open_month("c-1")

      r = report()

      refute @blocking_path in paths(r),
             "a queued job is \"not yet\", not \"never\" — without that the report lies " <>
               "on every ordinary delay"

      assert Enum.map(r.in_flight, &{&1.from, &1.to}) == [@blocking_path]
    end
  end

  describe "the shape of the report" do
    test "undeclared paths do not enter this list" do
      # Drift is a different question on the screen. Mixed into one list it turns
      # the report into a bag where "we did not do it" cannot be told apart from
      # "we did something we never agreed".
      open_month("c-1")

      Repo.insert!(%PNS.Event{
        type: "event_outside_the_contract",
        contract: inspect(Taxvision.Contracts.AccountingMonth),
        contract_version: Taxvision.Contracts.AccountingMonth.version(),
        correlation_id: Ecto.UUID.generate(),
        causation_id: List.first(events_of(:accounting_month_opened)).id,
        payload: %{},
        occurred_at: DateTime.utc_now()
      })

      assert Enum.all?(report().untraversed, & &1.handler)
    end

    test "one report per process rather than one global list" do
      # Notes §9: "navigation is per-process, never global".
      open_month("c-1")

      processes = PNS.Conformance.untraversed_paths() |> Enum.map(& &1.process)
      assert :accounting_month in processes
    end
  end
end
