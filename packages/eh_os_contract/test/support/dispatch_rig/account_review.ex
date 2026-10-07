defmodule DispatchRig.AccountReview do
  @moduledoc """
  # THIS PROCESS IS INVENTED. IT IS NOT CLIENT MATERIAL.

  **A process module over a contract's events** (plan DD, P2c, #210): an account's
  review runs from a withdrawal to the auditor's confirmation of its balance, both
  decided by `DispatchRig.Ledger`. Dispatch files each of them into this module's run
  as well, under its id and keyed by the account; the ledger's own runs stay as they
  are.
  """

  use EhOsContract.Process,
    id: "dispatch_rig.account_review",
    domain: DispatchRig.Domain,
    label: "Account review",
    accountable: :auditor

  correlate :account_id

  stage :withdrawal, include: [{DispatchRig.Ledger, :withdrawn}]
  stage :confirmation, include: [{DispatchRig.Ledger, :balance_confirmed}]

  ends_on :balance_confirmed
end
