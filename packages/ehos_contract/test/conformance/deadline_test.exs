defmodule EhosContract.DeadlineTest do
  @moduledoc """
  A process `deadline` measured on the new log (v2 §13, plan E7c): **the scenarios
  v1's deadline was measured on, with the outcomes v1 gave them.** Until v1 went
  (plan E11a) each ran on v1's shape too.

  A run's start and end come from `ehos_contract_event_runs`; the four outcomes and
  the period rule are `EhosContract.Run`'s. Since plan DD, P2g (#228) the processes
  measured are modules, `ProcessShapes.Timing` above all, and a run is named by the
  module's id.
  """

  use EhosContract.DataCase, async: false

  alias DispatchRig.Ledger.Commands.{Deposit, OpenAccount, Withdraw}
  alias ProcessShapes.{Seed, Timing}

  @nine ~U[2026-09-01 09:00:00.000000Z]
  @noon ~U[2026-09-01 12:00:00.000000Z]

  defp outcomes(opts \\ []) do
    Timing
    |> EhosContract.Run.evaluate("process_shapes.timing", Keyword.put_new(opts, :now, @noon))
    |> Map.new(&{&1.instance_id, &1.outcome})
  end

  describe "the deadline" do
    setup do: Seed.deploy()

    test "the four outcomes account for every run" do
      Seed.start_run("r-within", @nine)
      Seed.finish_run("r-within", ~U[2026-09-01 09:30:00.000000Z])
      Seed.start_run("r-exceeded", @nine)
      Seed.finish_run("r-exceeded", ~U[2026-09-01 10:30:00.000000Z])
      Seed.start_run("r-overdue", @nine)
      Seed.start_run("r-open", ~U[2026-09-01 11:50:00.000000Z])

      assert outcomes() == %{
               "process_shapes.timing|r-within" => :within,
               "process_shapes.timing|r-exceeded" => :exceeded,
               "process_shapes.timing|r-overdue" => :overdue,
               "process_shapes.timing|r-open" => :open
             }

      assert Timing
             |> EhosContract.Run.evaluate("process_shapes.timing", now: @noon)
             |> EhosContract.Run.summary() ==
               %{runs: 4, within: 1, exceeded: 1, overdue: 1, open: 1}
    end

    test "a run that started before the period is not in it, and is measured whole" do
      Seed.start_run("r-1", ~U[2026-08-31 23:00:00.000000Z])
      Seed.finish_run("r-1", ~U[2026-09-01 09:30:00.000000Z])

      assert outcomes(since: @nine) == %{}

      assert outcomes(since: ~U[2026-08-31 00:00:00.000000Z]) ==
               %{"process_shapes.timing|r-1" => :exceeded}
    end

    test "instance narrows to one run" do
      Seed.start_run("r-1", @nine)
      Seed.start_run("r-2", @nine)

      assert outcomes(instance: "process_shapes.timing|r-2") ==
               %{"process_shapes.timing|r-2" => :overdue}
    end

    test "an unconfirmed deadline is still measured; only the report leaves it out" do
      Seed.request("r-1", :request_approved)

      assert [%{instance_id: "process_shapes.handling|r-1", outcome: :within}] =
               EhosContract.Run.evaluate(ProcessShapes.Handling, "process_shapes.handling")
    end
  end

  describe "a process module" do
    # Until plan DD, P2g (#228) this was `DispatchRig.Branch`'s run of openings, which
    # nothing ended. A process module cannot declare a deadline without `ends_on` (R6),
    # so the run made of another contract's events is the account review's, which
    # includes the ledger's withdrawals and is not ended without a confirmation.
    test "measures a run made of another contract's events, which it includes (D7)" do
      clerk =
        EhosContract.Actor.credential("u-1", [
          "dispatch_rig.open_account",
          "dispatch_rig.deposit",
          "dispatch_rig.withdraw"
        ])

      EhosContract.Clock.at(@nine, fn ->
        for command <- [
              %OpenAccount{account_id: "a-1", branch_id: "b-7"},
              %Deposit{account_id: "a-1", amount: 100},
              %Withdraw{account_id: "a-1", amount: 50}
            ],
            do: {:ok, _} = EhosContract.dispatch(DispatchRig.Ledger, command, actor: clerk)
      end)

      # A second withdrawal joins the same run an hour later: the run starts at the
      # earliest of its events, not the latest.
      EhosContract.Clock.at(~U[2026-09-01 10:00:00.000000Z], fn ->
        {:ok, _} =
          EhosContract.dispatch(DispatchRig.Ledger, %Withdraw{account_id: "a-1", amount: 20},
            actor: clerk
          )
      end)

      assert [run] =
               EhosContract.Run.evaluate(
                 DispatchRig.AccountReview,
                 "dispatch_rig.account_review",
                 now: ~U[2026-09-04 09:00:00.000000Z]
               )

      assert %{
               instance_id: "dispatch_rig.account_review|a-1",
               started_at: @nine,
               ended_at: nil,
               outcome: :overdue
             } = run
    end

    test "a process that declares no deadline, and a name it does not have, have no outcomes" do
      assert EhosContract.Run.evaluate(DispatchRig.LedgerRun, "dispatch_rig.ledger_run",
               now: @noon
             ) == []

      assert EhosContract.Run.evaluate(Timing, "no_such", now: @noon) == []
    end
  end
end
