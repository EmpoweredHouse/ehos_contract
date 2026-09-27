defmodule ShreddingRig do
  @moduledoc """
  **An engine fixture, and invented.** Memberships whose events carry members'
  personal data, written to exercise crypto-shredding (v2 plan, E8): fields sealed
  in the log, keys per subject, and what a field reads back as once its key is gone.
  No workshop stands behind it, and no name in it comes from one.
  """

  use Boundary, deps: [EhOsContract], exports: [Domain, Members]
end
