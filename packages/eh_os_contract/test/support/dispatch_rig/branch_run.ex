defmodule DispatchRig.BranchRun do
  @moduledoc """
  # THIS PROCESS IS INVENTED. IT IS NOT CLIENT MATERIAL.

  **One event in two runs** (v2 §13, D7). An account's opening is decided by
  `DispatchRig.Ledger` and belongs to its account's run, `DispatchRig.LedgerRun`; this
  module includes it in a branch's run, correlated by the branch. v1 could not say
  that: one event, one process.

  Nothing ends a branch's run, so it declares no deadline, which a process module
  cannot measure without `ends_on` (R6). Until plan DD, P2g (#228) it was `:branch`
  inside `DispatchRig.Branch`, with a deadline of a day no run could be seen to meet.
  """

  use EhOsContract.Process,
    id: "dispatch_rig.branch_run",
    domain: DispatchRig.Domain,
    label: "Branch"

  correlate :branch_id

  stage :opening, include: [{DispatchRig.Ledger, :account_opened}]
end
