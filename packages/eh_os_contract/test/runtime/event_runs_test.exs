defmodule EhOsContract.EventRunsTest do
  @moduledoc """
  Every run an event belongs to (v2 §13, D7, plan E7c): its home run, and the run of
  each contract that includes it, written in the same append as the event.
  """

  use EhOsContract.DataCase, async: false

  alias DispatchRig.Ledger
  alias DispatchRig.Ledger.Commands.{Deposit, OpenAccount}
  alias EhOsContract.{Actor, Event, EventRun}

  @clerk Actor.credential("u-1", ["dispatch_rig.open_account", "dispatch_rig.deposit"])

  defp dispatch(command), do: {:ok, _} = EhOsContract.dispatch(Ledger, command, actor: @clerk)

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

  test "an event another contract includes belongs to its home run and to that contract's" do
    dispatch(%OpenAccount{account_id: "a-1", branch_id: "b-7"})

    assert runs("ledger.account_opened") == [{"branch", "branch|b-7"}, {"ledger", "ledger|a-1"}]
  end

  test "control: an event nobody includes belongs to its home run alone" do
    dispatch(%OpenAccount{account_id: "a-1", branch_id: "b-7"})
    dispatch(%Deposit{account_id: "a-1", amount: 10})

    assert runs("ledger.deposited") == [{"ledger", "ledger|a-1"}]
  end

  test "two accounts of one branch are two home runs and one branch run" do
    dispatch(%OpenAccount{account_id: "a-1", branch_id: "b-7"})
    dispatch(%OpenAccount{account_id: "a-2", branch_id: "b-7"})

    branch = for {"branch", id} <- runs("ledger.account_opened"), do: id
    assert branch == ["branch|b-7", "branch|b-7"]
  end

  describe "a run keyed by two fields" do
    alias ProcessShapes.Bare.Commands.OpenBatch

    @operator Actor.credential("u-1", ["process_shapes.open_batch"])

    test "is one run per pair of values, and a value shared with another pair merges nothing" do
      # `ProcessShapes.Bare` correlates on `[:tenant_id, :batch_id]`. Each pair
      # below shares one value with another, so a key built from either field alone
      # would merge two of them into one run.
      for {tenant, batch} <- [{"t-1", "b-1"}, {"t-1", "b-2"}, {"t-2", "b-1"}] do
        {:ok, _} =
          EhOsContract.dispatch(
            ProcessShapes.Bare,
            %OpenBatch{tenant_id: tenant, batch_id: batch},
            actor: @operator
          )
      end

      # The values in the order `correlate` declares them, after the process's name.
      assert runs("batching.batch_opened") == [
               {"batching", "batching|t-1|b-1"},
               {"batching", "batching|t-1|b-2"},
               {"batching", "batching|t-2|b-1"}
             ]
    end
  end
end
