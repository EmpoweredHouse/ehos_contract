defmodule ReadRig do
  @moduledoc """
  **An engine fixture, and invented.** A shop whose order reads the product it names,
  written to exercise a command that reads an entity the application keeps (plan DD,
  T2a, #240), and nothing more: no workshop stands behind it, and no name in it comes
  from one. A clinic's booking that reads its service is what it is shaped after.
  """

  use Boundary, deps: [EhOsContract], exports: [Domain, Entities, Orders]
end
