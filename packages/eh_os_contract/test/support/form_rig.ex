defmodule FormRig do
  @moduledoc """
  **An engine fixture, and invented.** An invoice issued from a form, written to exercise
  `EhOsContract.Form`: a command with a field of every built-in type and a domain value
  with an invariant. No workshop stands behind it, and no name in it comes from one.
  """

  use Boundary, deps: [EhOsContract], exports: [Domain, Invoicing]
end
