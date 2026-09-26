defmodule EhOsContract.DeadlineTest do
  @moduledoc """
  A process `deadline` measured on the new log (v2 §13, plan E7c): **the scenarios of
  `run_test.exs`, on `ProcessShapes.Timed` and on its v2 port, with the same
  expected outcomes.** Each test runs once per shape.

  On v2 a run's start and end come from `eh_os_contract_event_runs`; the four
  outcomes and the period rule are `EhOsContract.Run`'s, shared.
  """

  use EhOsContract.DataCase, async: false

  alias ProcessShapes.Seed

  @nine ~U[2026-09-01 09:00:00.000000Z]
  @noon ~U[2026-09-01 12:00:00.000000Z]

  defp outcomes(shape, opts \\ []) do
    shape
    |> Seed.timed()
    |> EhOsContract.Run.evaluate(:timed_run, Keyword.put_new(opts, :now, @noon))
    |> Map.new(&{&1.instance_id, &1.outcome})
  end

  for shape <- [:v1, :v2] do
    describe "#{shape}:" do
      @describetag shape: shape

      setup %{shape: shape}, do: Seed.deploy(shape)

      test "the four outcomes account for every run", %{shape: shape} do
        Seed.start_run(shape, "r-within", @nine)
        Seed.finish_run(shape, "r-within", ~U[2026-09-01 09:30:00.000000Z])
        Seed.start_run(shape, "r-exceeded", @nine)
        Seed.finish_run(shape, "r-exceeded", ~U[2026-09-01 10:30:00.000000Z])
        Seed.start_run(shape, "r-overdue", @nine)
        Seed.start_run(shape, "r-open", ~U[2026-09-01 11:50:00.000000Z])

        assert outcomes(shape) == %{
                 "timed_run|r-within" => :within,
                 "timed_run|r-exceeded" => :exceeded,
                 "timed_run|r-overdue" => :overdue,
                 "timed_run|r-open" => :open
               }

        assert shape
               |> Seed.timed()
               |> EhOsContract.Run.evaluate(:timed_run, now: @noon)
               |> EhOsContract.Run.summary() ==
                 %{runs: 4, within: 1, exceeded: 1, overdue: 1, open: 1}
      end

      test "a run that started before the period is not in it, and is measured whole", %{
        shape: shape
      } do
        Seed.start_run(shape, "r-1", ~U[2026-08-31 23:00:00.000000Z])
        Seed.finish_run(shape, "r-1", ~U[2026-09-01 09:30:00.000000Z])

        assert outcomes(shape, since: @nine) == %{}

        assert outcomes(shape, since: ~U[2026-08-31 00:00:00.000000Z]) ==
                 %{"timed_run|r-1" => :exceeded}
      end

      test "instance narrows to one run", %{shape: shape} do
        Seed.start_run(shape, "r-1", @nine)
        Seed.start_run(shape, "r-2", @nine)

        assert outcomes(shape, instance: "timed_run|r-2") == %{"timed_run|r-2" => :overdue}
      end

      test "an unconfirmed deadline is still measured; only the report leaves it out", %{
        shape: shape
      } do
        Seed.request(shape, "r-1", :request_approved)

        assert [%{instance_id: "handling|r-1", outcome: :within}] =
                 EhOsContract.Run.evaluate(Seed.promised(shape), :handling)
      end
    end
  end

  describe "a v2 contract" do
    test "measures a run made of another contract's events, which it includes (D7)" do
      clerk = EhOsContract.Actor.credential("u-1", ["dispatch_rig.open_account"])

      for {account, at} <- [{"a-1", @nine}, {"a-2", ~U[2026-09-01 10:00:00.000000Z]}] do
        EhOsContract.Clock.at(at, fn ->
          {:ok, _} =
            EhOsContract.dispatch(
              DispatchRig.Ledger,
              %DispatchRig.Ledger.Commands.OpenAccount{account_id: account, branch_id: "b-7"},
              actor: clerk
            )
        end)
      end

      assert [run] =
               EhOsContract.Run.evaluate(DispatchRig.Branch, :branch,
                 now: ~U[2026-09-03 09:00:00.000000Z]
               )

      assert %{instance_id: "branch|b-7", started_at: @nine, ended_at: nil, outcome: :overdue} =
               run
    end

    test "a process that declares no deadline, and a name it does not have, have no outcomes" do
      assert EhOsContract.Run.evaluate(DispatchRig.Ledger, :ledger, now: @noon) == []
      assert EhOsContract.Run.evaluate(ProcessShapes.Next.Timed, :no_such, now: @noon) == []
    end
  end
end
