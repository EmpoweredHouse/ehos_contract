defmodule DispatchRig.Transfer do
  @moduledoc """
  # THIS CONTRACT IS INVENTED. IT IS NOT CLIENT MATERIAL.

  A scoped command (plan E9c): a clerk moves an account only into a branch their
  grant names. A contract of its own, so that `DispatchRig.Ledger`'s pinned digest
  keeps saying what it says.
  """

  use EhOsContract.Contract,
    domain: DispatchRig.Domain,
    context: :ledger,
    id: "dispatch_rig.transfer"

  aggregate :transfer, "Transfer" do
    identity :account_id

    command :move_account, "Move the account to a branch",
      by: :clerk,
      scope: :branch_id,
      emits: :account_moved do
      field :branch_id, :id
    end

    event :account_moved, "Account moved to a branch" do
      field :branch_id, :id
    end
  end

  process :transfer, "Transfer" do
    correlate :account_id
  end

  scenario "an account is moved to a branch" do
    command :move_account, %{branch_id: "b-7"}
    expect :account_moved, %{branch_id: "b-7"}
  end
end

defmodule DispatchRig.TransferDecider do
  @moduledoc "**Invented.** The decider of `DispatchRig.Transfer`."

  use DispatchRig.Transfer, aggregate: :transfer

  @impl true
  def move_account(%MoveAccount{account_id: id, branch_id: branch}, _state),
    do: emit(%AccountMoved{account_id: id, branch_id: branch})
end
