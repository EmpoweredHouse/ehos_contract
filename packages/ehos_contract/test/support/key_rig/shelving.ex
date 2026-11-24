defmodule KeyRig.Shelving do
  @moduledoc """
  # THIS PROCESS IS INVENTED. IT IS NOT CLIENT MATERIAL.

  A shelf's run, keyed by its site alone (issue #98): see `KeyRig.Shelves`. Until plan
  DD, P2g (#228) it was `:shelving` inside the contract.
  """

  use EhosContract.Process,
    id: "key_rig.shelving",
    domain: KeyRig.Domain,
    label: "Shelving",
    accountable: :stocker

  correlate :site_id

  stage :stock, include: [{KeyRig.Shelves, :loaded}]
end
