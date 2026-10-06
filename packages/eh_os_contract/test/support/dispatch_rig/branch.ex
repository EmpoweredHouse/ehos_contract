defmodule DispatchRig.Branch do
  @moduledoc """
  # THIS CONTRACT IS INVENTED. IT IS NOT CLIENT MATERIAL.

  **One event in two processes** (v2 §13, D7). An account's opening is decided by
  `DispatchRig.Ledger` and belongs to its account's run there; this contract
  includes it in a branch's run, correlated by the branch. v1 could not say that:
  one event, one process.

  It declares nothing of its own, which a contract may (D3): its whole content is
  the run it draws over another contract's events.
  """

  use EhOsContract.Contract,
    domain: DispatchRig.Domain,
    context: :ledger,
    id: "dispatch_rig.branch"

  consumes DispatchRig.Ledger, :account_opened

  process :branch, "Branch" do
    correlate :branch_id
    include :account_opened

    # So that a reader of runs has something to measure on a run made only of another
    # contract's events. Nothing ends a branch's run, so every one is open or overdue.
    deadline {1, :day}
  end
end
