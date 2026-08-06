defmodule PNS.DependencyTest do
  @moduledoc """
  Stage 1.5b: **the fourth verdict, `:suspended`.**

  `external` and `unavailable_looks_like` had been in the contract from the first day and
  nothing read them. Until now a registry outage inside an assertion window counted as
  `:violated` — the report told a client they broke their own agreement while somebody
  else's server was down, which is the most expensive false positive this product can
  produce, because the report's only asset is being believed.

  Exercised on the shapes rig rather than on TaxVision, and that is a finding rather than
  a convenience: **TaxVision cannot produce a suspension.** Its one declared dependency,
  the public registries, is consulted by the request edge *before* the first event is
  emitted, so the window never opens while the dependency is in play. This verdict matters
  for processes whose **consequent** reaches outside, not whose precondition does.
  """

  use Taxvision.DataCase, async: false

  alias ProcessShapes.Rig

  @trace :submission_reaches_inspection
  @submitted ~U[2026-07-01 09:00:00.000000Z]
  # `within: {1, :day}`, so the window closes here.
  @deadline ~U[2026-07-02 09:00:00.000000Z]
  @after_window ~U[2026-07-05 09:00:00.000000Z]

  defp submit(case_id, at) do
    Repo.insert!(%PNS.Event{
      type: "item_submitted",
      contract: inspect(Rig),
      contract_version: Rig.version(),
      process: "pairing",
      instance_id: "pairing|#{case_id}",
      correlation_id: Ecto.UUID.generate(),
      payload: %{"case_id" => case_id, "item_no" => 1},
      occurred_at: at
    })
  end

  defp outage(at, external \\ :inspection_service) do
    PNS.Dependency.unavailable!(Rig, external, "test", at)
  end

  defp verdicts, do: PNS.Trace.evaluate(Rig, @trace, now: @after_window)
  defp verdict, do: List.first(verdicts())

  describe "the verdict a run gets" do
    test "without an outage the window closing is a violation, as before" do
      # The control, and it has to come first: everything below is about *replacing* this
      # verdict, so if it were not produced there would be nothing to replace.
      submit("c-1", @submitted)

      assert verdict().verdict == :violated
    end

    test "an outage inside the window suspends instead" do
      submit("c-1", @submitted)
      outage(~U[2026-07-01 15:00:00.000000Z])

      assert verdict().verdict == :suspended
    end

    test "an outage outside the window does not" do
      # Two boundaries in one test, because an off-by-one here silently excuses runs.
      submit("c-1", @submitted)
      outage(~U[2026-06-30 09:00:00.000000Z])
      outage(~U[2026-07-03 09:00:00.000000Z])

      assert verdict().verdict == :violated
    end

    test "the window's edges count as inside it" do
      submit("c-1", @submitted)
      outage(@deadline)

      assert verdict().verdict == :suspended
    end
  end

  describe "what a suspension may not take" do
    test "it never replaces a satisfied verdict" do
      # A run that ended correctly ended correctly, whatever was down at the time. Folding
      # these together would let an outage erase a success, which is nonsense in the
      # direction nobody would think to check.
      submit("c-1", @submitted)
      outage(~U[2026-07-01 15:00:00.000000Z])

      Repo.insert!(%PNS.Event{
        type: "item_inspected",
        contract: inspect(Rig),
        contract_version: Rig.version(),
        process: "pairing",
        instance_id: "pairing|c-1",
        correlation_id: Ecto.UUID.generate(),
        payload: %{"case_id" => "c-1", "item_no" => 1},
        occurred_at: ~U[2026-07-01 18:00:00.000000Z]
      })

      assert verdict().verdict == :satisfied
    end

    test "it never replaces a pending verdict" do
      # There is still time. Suspending now would answer a question nobody has asked yet.
      submit("c-1", @submitted)
      outage(~U[2026-07-01 15:00:00.000000Z])

      inside = PNS.Trace.evaluate(Rig, @trace, now: ~U[2026-07-01 20:00:00.000000Z])

      assert List.first(inside).verdict == :pending
    end
  end

  describe "which dependency counts" do
    test "one the awaited event does not declare is irrelevant" do
      # Taking the union of a contract's dependencies would excuse a run because something
      # it never touched was down. `item_inspected` declares `:inspection_service` and
      # nothing else.
      submit("c-1", @submitted)

      assert_raise ArgumentError, ~r/does not declare `external :postal_service`/, fn ->
        outage(~U[2026-07-01 15:00:00.000000Z], :postal_service)
      end

      assert verdict().verdict == :violated
    end

    test "an observation about an undeclared dependency is refused outright" do
      # It could never reach an assertion, so recording it would be writing to a place
      # nothing reads — the same argument the compile gate makes about `depends_on`.
      assert_raise ArgumentError, ~r/could never reach an assertion/, fn ->
        PNS.Dependency.unavailable!(Rig, :something_nobody_declared)
      end
    end
  end

  describe "recording, which is wrapped rather than remembered" do
    test "an adapter reporting :unavailable is recorded" do
      result =
        PNS.Dependency.observe(Rig, :inspection_service, fn -> {:error, :unavailable} end)

      assert result == {:error, :unavailable}
      assert [observation] = Repo.all(PNS.Dependency)
      assert observation.external == "inspection_service"
    end

    test "any other error is passed through and **not** recorded" do
      # The direction that matters. A suspension deletes a finding from the report, so a
      # wrapper treating every failure as an outage would quietly stop reporting real
      # problems — failing where nobody notices, which is the opposite of the rest of this
      # engine.
      assert PNS.Dependency.observe(Rig, :inspection_service, fn -> {:error, :timeout} end) ==
               {:error, :timeout}

      assert Repo.all(PNS.Dependency) == []
    end

    test "success is passed through untouched" do
      assert PNS.Dependency.observe(Rig, :inspection_service, fn -> {:ok, :fine} end) ==
               {:ok, :fine}

      assert Repo.all(PNS.Dependency) == []
    end
  end

  describe "the summary keeps them apart" do
    test "a suspension is not counted among the breaches" do
      submit("c-1", @submitted)
      submit("c-2", @submitted)
      outage(~U[2026-07-01 15:00:00.000000Z])

      summary = PNS.Trace.summary(verdicts())

      # Both runs are suspended by one outage, because an outage is not per company.
      assert summary.suspended == 2
      assert summary.violated == 0
      assert summary.instances == 2
    end
  end
end
