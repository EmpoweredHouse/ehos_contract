defmodule EhOsContract.DispatchCommandScopeTest do
  @moduledoc """
  A scoped command (plan E9c, D10 for commands): a credential is asked for the
  command's capability with the value of its scope field, as a scoped query is, so a
  value outside the grant is refused before anything is decided.
  """

  use EhOsContract.DataCase, async: false

  alias DispatchRig.Transfer
  alias DispatchRig.Transfer.Commands.MoveAccount
  alias EhOsContract.{Actor, Event}

  @move "dispatch_rig.move_account"

  defp clerk(branches),
    do: Actor.credential("u-1", [@move], %{@move => %{"branch_id" => branches}})

  defp move(branch, actor),
    do:
      EhOsContract.dispatch(Transfer, %MoveAccount{account_id: "a-1", branch_id: branch},
        actor: actor
      )

  test "the model's capability carries the command's scope" do
    assert %{
             kind: :command,
             name: :move_account,
             scope: :branch_id,
             roles: ["dispatch_rig.clerk"]
           } =
             EhOsContract.Model.capabilities(Transfer)[@move]

    # Control: an unscoped command's has none.
    assert %{scope: nil} =
             EhOsContract.Model.capabilities(DispatchRig.Ledger)["dispatch_rig.deposit"]
  end

  test "a value within the grant is decided" do
    assert {:ok, _} = move("b-7", clerk(["b-7", "b-9"]))
    assert Repo.all(from(e in Event, select: e.type)) == ["transfer.account_moved"]
  end

  test "a value outside the grant is refused, and nothing is appended" do
    assert move("b-9", clerk(["b-7"])) == {:error, :outside_scope}
    assert Repo.aggregate(Event, :count) == 0
  end

  test "a scoped command granted with no values is refused: fail closed" do
    assert move("b-7", clerk([])) == {:error, :unscoped_grant}
    assert move("b-7", Actor.credential("u-1", [@move])) == {:error, :unscoped_grant}
  end

  test "a scope field that does not fit its type is asked with no value, and refused" do
    # Asked before the fields are checked, so a caller without the grant learns nothing
    # about them; the value that does not decode is no value (plan E9c review).
    assert move(%{"not" => "an id"}, clerk(["b-7"])) == {:error, :outside_scope}
    assert move(7, clerk(["b-7"])) == {:error, :outside_scope}
  end
end
