defmodule DispatchRig.AccountReview do
  @moduledoc """
  # THIS PROCESS IS INVENTED. IT IS NOT CLIENT MATERIAL.

  **A process module over a contract's events** (plan DD, P2c, #210): an account's
  review runs from a withdrawal to the auditor's confirmation of its balance, both
  decided by `DispatchRig.Ledger`. Dispatch files each of them into this module's run
  as well, under its id and keyed by the account; the ledger's own runs stay as they
  are.

  A review is agreed to take two days, and the auditor promises to confirm the balance
  within a day of a withdrawal (plan DD, P2d, #213): what the report judges a process
  module's runs by.
  """

  use EhOsContract.Process,
    id: "dispatch_rig.account_review",
    domain: DispatchRig.Domain,
    label: "Account review",
    accountable: :auditor

  correlate :account_id

  stage :withdrawal, "Withdrawal", include: [{DispatchRig.Ledger, :withdrawn}]
  stage :confirmation, "Confirmation", include: [{DispatchRig.Ledger, :balance_confirmed}]

  ends_on :balance_confirmed

  deadline {2, :day}

  promise :balance_confirmed_after_withdrawal do
    from :withdrawn
    eventually :balance_confirmed
    within {1, :day}
  end
end
