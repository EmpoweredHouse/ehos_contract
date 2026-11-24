defmodule DispatchRig.Branch do
  @moduledoc """
  # THIS CONTRACT IS INVENTED. IT IS NOT CLIENT MATERIAL.

  **A contract that consumes a sibling's event and declares nothing of its own**,
  which a contract may (D3): an account's opening, decided by `DispatchRig.Ledger`. It
  is what the pages, the system's graph and the index of contracts by id read a
  sibling's consumer from.

  Until plan DD, P2g (#228) it also drew a branch's run over that event; the run is
  `DispatchRig.BranchRun`'s now, a process module, which includes the event from the
  ledger itself.
  """

  use EhosContract.Contract,
    domain: DispatchRig.Domain,
    context: :ledger,
    id: "dispatch_rig.branch"

  consumes DispatchRig.Ledger, :account_opened
end
