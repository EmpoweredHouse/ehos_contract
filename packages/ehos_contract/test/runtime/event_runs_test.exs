defmodule EhosContract.EventRunsTest do
  @moduledoc """
  Every run an event belongs to (v2 §13, D7, plan E7c): the run of each process that
  includes it, written in the same append as the event. Since plan DD, P2g (#228) the
  ledger's runs are process modules', `DispatchRig.LedgerRun` and
  `DispatchRig.BranchRun`, filed under their ids.
  """

  use EhosContract.DataCase, async: false

  alias DispatchRig.Ledger
  alias DispatchRig.Ledger.Commands.{Deposit, OpenAccount}
  alias EhosContract.{Actor, Event, EventRun}

  @clerk Actor.credential("u-1", ["dispatch_rig.open_account", "dispatch_rig.deposit"])

  defp dispatch(command), do: {:ok, _} = EhosContract.dispatch(Ledger, command, actor: @clerk)

  defp runs(type) do
    Repo.all(
      from(r in EventRun,
        join: e in Event,
        on: e.position == r.position,
        where: e.type == ^type,
        order_by: [e.position, r.process],
        select: {r.process, r.instance_id}
      )
    )
  end

  test "an event two processes include belongs to the run of each" do
    dispatch(%OpenAccount{account_id: "a-1", branch_id: "b-7"})

    assert runs("dispatch_rig.ledger.account_opened") == [
             {"dispatch_rig.branch_run", "dispatch_rig.branch_run|b-7"},
             {"dispatch_rig.ledger_run", "dispatch_rig.ledger_run|a-1"}
           ]
  end

  test "control: an event one process includes belongs to its run alone" do
    dispatch(%OpenAccount{account_id: "a-1", branch_id: "b-7"})
    dispatch(%Deposit{account_id: "a-1", amount: 10})

    assert runs("dispatch_rig.ledger.deposited") == [
             {"dispatch_rig.ledger_run", "dispatch_rig.ledger_run|a-1"}
           ]
  end

  test "two accounts of one branch are two account runs and one branch run" do
    dispatch(%OpenAccount{account_id: "a-1", branch_id: "b-7"})
    dispatch(%OpenAccount{account_id: "a-2", branch_id: "b-7"})

    branch =
      for {"dispatch_rig.branch_run", id} <- runs("dispatch_rig.ledger.account_opened"), do: id

    assert branch == ["dispatch_rig.branch_run|b-7", "dispatch_rig.branch_run|b-7"]
  end

  describe "a run keyed by two fields" do
    alias ProcessShapes.Bare.Commands.OpenBatch

    @operator Actor.credential("u-1", ["process_shapes.open_batch"])

    test "is one run per pair of values, and a value shared with another pair merges nothing" do
      # `ProcessShapes.Batching` correlates on `[:tenant_id, :batch_id]`. Each pair
      # below shares one value with another, so a key built from either field alone
      # would merge two of them into one run.
      for {tenant, batch} <- [{"t-1", "b-1"}, {"t-1", "b-2"}, {"t-2", "b-1"}] do
        {:ok, _} =
          EhosContract.dispatch(
            ProcessShapes.Bare,
            %OpenBatch{tenant_id: tenant, batch_id: batch},
            actor: @operator
          )
      end

      # The values in the order `correlate` declares them, after the process's id.
      assert runs("process_shapes.bare.batch_opened") == [
               {"process_shapes.batching", "process_shapes.batching|t-1|b-1"},
               {"process_shapes.batching", "process_shapes.batching|t-1|b-2"},
               {"process_shapes.batching", "process_shapes.batching|t-2|b-1"}
             ]
    end
  end
end
