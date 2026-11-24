defmodule EhosContract.SubscriptionsTaskTest do
  @moduledoc """
  `mix ehos_contract.subscriptions` (plan E7a): where each subscription stands, and
  a person's two decisions about a failing one, `--skip` and `--reset`.
  """

  use EhosContract.DataCase, async: false

  import ExUnit.CaptureIO

  alias DispatchRig.Ledger
  alias DispatchRig.Ledger.Commands.{Deposit, OpenAccount}
  alias EhosContract.{Actor, Testing}
  alias Mix.Tasks.EhosContract.Subscriptions

  @moduletag :capture_log

  @clerk Actor.credential("u-1", ["dispatch_rig.open_account", "dispatch_rig.deposit"])
  @lines "dispatch_rig.ledger:read_model:ledger_lines"

  defp dispatch(command), do: {:ok, _} = EhosContract.dispatch(Ledger, command, actor: @clerk)
  defp task(args), do: capture_io(fn -> Subscriptions.run(args) end)

  defp amounts,
    do: Repo.all(from(l in "dispatch_rig_lines", order_by: l.position, select: l.amount))

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)

    dispatch(%OpenAccount{account_id: "a-1", branch_id: "b-7"})
    for amount <- [10, 31, 20], do: dispatch(%Deposit{account_id: "a-1", amount: amount})
    Testing.drain()
    :ok
  end

  defp output do
    receive do
      {:mix_shell, :info, [text]} -> text
    after
      0 -> flunk("the task printed nothing")
    end
  end

  test "lists every subscription, and where a failing one fails" do
    task([])
    text = output()

    assert text =~
             ~r/^dispatch_rig\.ledger:read_model:ledger_lines  failing at \d+, fails at \d+ \(RuntimeError, 3 attempts\)$/m

    assert text =~ ~r/^dispatch_rig\.ledger:read_model:balances  running at \d+$/m
    assert text =~ ~r/^dispatch_rig\.ledger:policy:flag_large_withdrawal  running at \d+$/m
  end

  test "--skip moves it past the poison event, and the next drain applies the rest" do
    task(["--skip", @lines])
    assert output() =~ "moved past the event it failed on"

    Testing.drain()
    assert amounts() == [10, 20]
  end

  test "--reset replays the log, which fails on the poison again" do
    task(["--reset", @lines])
    assert output() =~ "emptied, and replayed"
    assert amounts() == []

    assert %{failing: [@lines]} = Testing.drain()
    assert amounts() == [10]
  end

  test "refuses what a person cannot decide" do
    assert_raise Mix.Error, ~r/is not failing/, fn ->
      task(["--skip", "dispatch_rig.ledger:read_model:balances"])
    end

    assert_raise Mix.Error, ~r/defines no reset\/0/, fn ->
      task(["--reset", "dispatch_rig.ledger:read_model:movements"])
    end
  end

  test "--reset of a relay moves it back, to publish the log again" do
    task(["--reset", "bus_rig_shop.orders:relay:order_placed"])
    assert output() =~ "moved back to the beginning of the log, to publish it again"

    assert Repo.get!(EhosContract.SubscriptionRecord, "bus_rig_shop.orders:relay:order_placed").position ==
             0
  end

  test "--reset of a policy moves it back, to react to the log" do
    task(["--reset", "dispatch_rig.ledger:policy:flag_large_withdrawal"])
    assert output() =~ "moved back to the beginning of the log, to react to it"
  end
end
