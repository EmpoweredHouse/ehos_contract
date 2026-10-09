defmodule AppuniteEquipment.Processes do
  @moduledoc """
  The runs the equipment manager chose to verify, as process modules (plan DD, P2f,
  #222): one assignment of a computer, from the issue to its return. A process module
  names the contracts whose events it includes without a compile dependency on them,
  and nothing calls it: dispatch finds it in the running binary.
  """

  use Boundary, deps: [EhOsContract], exports: []
end
