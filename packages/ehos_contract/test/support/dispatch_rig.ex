defmodule DispatchRig do
  @moduledoc """
  **An engine fixture, and invented.** A ledger of accounts, written to exercise v2
  dispatch (v2 plan, E6) the way v1's process-shapes rig exercised v1's emitter, and
  nothing more: no workshop stands behind it, and no name in it comes from one.

  It inherits the parts of that rig the plan gave to E6: a decision that returns what it does not
  declare, and consumers that run inside the dispatch transaction.
  """

  use Boundary, deps: [EhosContract], exports: [Branch, Domain, Ledger, Unfinished]
end
