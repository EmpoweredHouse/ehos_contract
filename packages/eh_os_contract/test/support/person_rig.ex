defmodule PersonRig do
  @moduledoc """
  **An engine fixture, and invented.** A help desk whose ticket is resolved only by the
  clerk it is assigned to, written to exercise a command that names the person who must
  issue it (plan DD, A1, #247), and nothing more: no workshop stands behind it, and no
  name in it comes from one. Rehmed's clinical close by the visit's own specialist is
  what it is shaped after.
  """

  use Boundary, deps: [EhOsContract], exports: [Domain, Desk]
end
