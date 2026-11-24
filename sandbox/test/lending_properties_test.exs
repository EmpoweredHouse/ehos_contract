defmodule Lending.CirculationPropertiesTest do
  @moduledoc """
  The loan's and the copy's decisions tried on legal histories of their contract:
  every history folds, every command decides within the contract, and the loan's
  invariants hold after every decided command, as `holds?/2` says. The hold is a
  boundary, which `EhosContract.PropertyCase` leaves out.
  """

  use EhosContract.PropertyCase, contract: Lending.Contracts.Circulation, max_runs: 100

  alias Lending.Contracts.Circulation
  alias Lending.Contracts.Circulation.Commands.{LendCopy, ReturnCopy, WaiveLateFee}

  test "a copy back late, its fee waived: nothing is owed" do
    commands = [
      {%LendCopy{
         loan_id: "loan-1",
         copy_id: "copy-1",
         member_id: "member-ada",
         card_id: "card-ada",
         due_at: ~U[2026-01-22 17:00:00Z]
       }, %{card: %{card_id: "card-ada", suspended: false}}},
      {%ReturnCopy{loan_id: "loan-1", late_fee: 150}, %{}},
      {%WaiveLateFee{loan_id: "loan-1"}, %{}}
    ]

    assert %{lent: true, returned: true, fee_owed: false} =
             EhosContract.PropertyCase.walk(Circulation, :loan, commands)
  end
end
