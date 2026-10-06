defmodule KeyRig.Audit do
  @moduledoc """
  # THIS CONTRACT IS INVENTED. IT IS NOT CLIENT MATERIAL.

  A stocked bin in a run of another process, correlated by its lot instead of its
  bin: an included run, whose key `KeyRig.Bins`'s own keys do not bound (issue #98).
  """

  use EhOsContract.Contract, domain: KeyRig.Domain, context: :stock, id: "key_rig.audit"

  consumes KeyRig.Bins, :restocked

  process :audit_trail, "Audit trail", accountable: :stocker do
    correlate [:site_id, :aisle_id, :lot_id]
    include :restocked
  end
end
