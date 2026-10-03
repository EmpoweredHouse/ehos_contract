defmodule KeyRig do
  @moduledoc """
  **An engine fixture, and invented.** Bins and shelves in a warehouse, each
  addressed by three `:id` fields, the fewest whose key can be longer than
  `EhOsContract.Key.budget/0` (issue #98): a stream, a home run, an included run and a
  process manager's run, each of a different length over the same values, so that one
  set of values fits one and not the next. Nothing else: no workshop stands behind
  it, and no name in it comes from one.
  """

  use Boundary, deps: [EhOsContract], exports: [Audit, Bins, Domain, Shelves]
end
