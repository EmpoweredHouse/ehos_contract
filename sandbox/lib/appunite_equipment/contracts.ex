defmodule AppuniteEquipment.Contracts do
  @moduledoc """
  The computer, which decides everything about itself
  (`AppuniteEquipment.Contracts.Computers`), and the demand, a person who needs a
  computer until one is issued to them (`AppuniteEquipment.Contracts.Demands`). The
  assignment, a run over the computer's events, is a process module,
  `AppuniteEquipment.Processes.Assignment` (plan DD, P2f, #222).
  """

  use Boundary,
    deps: [EhOsContract],
    exports: [{Computers, []}, {Demands, []}]
end
