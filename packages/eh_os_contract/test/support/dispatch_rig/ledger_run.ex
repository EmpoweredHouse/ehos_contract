defmodule DispatchRig.LedgerRun do
  @moduledoc """
  # THIS PROCESS IS INVENTED. IT IS NOT CLIENT MATERIAL.

  An account's run through the ledger: every event `DispatchRig.Ledger` declares,
  keyed by the account. Nothing ends it, and it keeps no promise and no deadline: a
  run that is only counted. Until plan DD, P2g (#228) it was `:ledger` inside the
  contract.
  """

  use EhOsContract.Process,
    id: "dispatch_rig.ledger_run",
    domain: DispatchRig.Domain,
    label: "Ledger"

  correlate :account_id

  stage :account,
    include: [
      {DispatchRig.Ledger,
       [
         :account_opened,
         :deposited,
         :withdrawn,
         :account_flagged,
         :interest_recorded,
         :balance_confirmed,
         :day_closed
       ]}
    ]
end
