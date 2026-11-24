defmodule KeyRig do
  @moduledoc """
  **An engine fixture, and invented.** Bins and shelves in a warehouse, each
  addressed by three `:id` fields, the fewest whose key can be longer than
  `EhosContract.Key.budget/0` (issue #98): a stream, a run keyed by the bin, a run keyed
  by its lot and a process manager's run, each of a different length over the same
  values, so that one set of values fits one and not the next. The runs are process
  modules' since plan DD, P2g (#228). Nothing else: no workshop stands behind it, and
  no name in it comes from one.
  """

  use Boundary, deps: [EhosContract], exports: [Bins, Domain, Shelves]
end
