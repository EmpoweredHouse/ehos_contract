defmodule ValueRig do
  @moduledoc """
  **An engine fixture, and invented.** A till that takes payments, written to exercise
  the invariants of domain values (plan EL2b): a value's check in dispatch, in a
  recorded event, in a query's parameters and around a domain service, and the tests
  generated from each invariant's examples and each rule's. No workshop stands behind
  it, and no name in it comes from one.
  """

  use Boundary, deps: [EhOsContract], exports: [Domain, Till]
end
