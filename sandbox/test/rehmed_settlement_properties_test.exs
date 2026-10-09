defmodule Rehmed.SettlementPropertiesTest do
  @moduledoc """
  Plan DD, PC2 (#266): the settlement's decider tried on legal histories of its
  contract: every history folds, every command decides within the contract, and its
  invariants hold after every decided command, as `holds?/2` says.
  """

  use EhOsContract.PropertyCase, contract: Rehmed.Contracts.Settlement, max_runs: 100

  alias Rehmed.Contracts.Settlement.Commands.{CloseSettlement, RecordPayment}

  # Payments that sum to nothing close the visit without payment, as the decider reads
  # them; the invariant agrees.
  test "payments summing to nothing close without payment, and the sum still holds" do
    commands = [
      {%RecordPayment{visit_id: "visit-1", method: :card, amount: 0}, %{}},
      {%CloseSettlement{visit_id: "visit-1", total: 10_000}, %{}}
    ]

    assert %{closed_on: %Date{}, payments: [0], total: 10_000} =
             EhOsContract.PropertyCase.walk(
               Rehmed.Contracts.Settlement,
               :visit_settlement,
               commands
             )
  end
end
