defmodule SupplyRig do
  @moduledoc """
  **An engine fixture, and invented.** A desk that closes visits and notes arrivals, with
  one field of each that the host supplies (plan T1): whether a visit's report went out,
  and when a patient arrived. No workshop stands behind it, and no name in it comes from
  one; `Rehmed`'s `p1_reported` is what it is shaped after.
  """

  use Boundary, deps: [EhOsContract], exports: [Domain, Desk, Supplier]
end
