defmodule KeyRig.Restocking do
  @moduledoc """
  # THIS PROCESS IS INVENTED. IT IS NOT CLIENT MATERIAL.

  A bin's run, keyed by the bin's identity: `KeyRig.Bins`'s events. Its id is in the
  run's entry twice, as the process column and the instance id's prefix, so it is
  kept two bytes shorter than what would make the run's key longer than the watch's
  (issue #98). Until plan DD, P2g (#228) it was `:replenishment` inside the contract;
  the id and the label now name it after the restock that starts it.
  """

  use EhOsContract.Process,
    id: "key_rig.restocking",
    domain: KeyRig.Domain,
    label: "Restocking",
    accountable: :stocker

  correlate [:site_id, :aisle_id, :bin_id]

  stage :stock, include: [{KeyRig.Bins, [:restocked, :counted]}]
end
