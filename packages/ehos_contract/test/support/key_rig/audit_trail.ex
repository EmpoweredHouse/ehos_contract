defmodule KeyRig.AuditTrail do
  @moduledoc """
  # THIS PROCESS IS INVENTED. IT IS NOT CLIENT MATERIAL.

  A stocked bin in a run of another process, correlated by its lot instead of its
  bin: a run whose key `KeyRig.Bins`'s own keys do not bound (issue #98). Until plan
  DD, P2g (#228) it was `:audit_trail` in a contract of its own, `KeyRig.Audit`, which
  consumed the restock only to include it and declared nothing else, so it went with
  the run; this module includes the restock from `KeyRig.Bins`.
  """

  use EhosContract.Process,
    id: "key_rig.audit_trail",
    domain: KeyRig.Domain,
    label: "Audit trail",
    accountable: :stocker

  correlate [:site_id, :aisle_id, :lot_id]

  stage :restock, include: [{KeyRig.Bins, :restocked}]
end
