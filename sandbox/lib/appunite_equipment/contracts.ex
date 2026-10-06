defmodule AppuniteEquipment.Contracts do
  @moduledoc """
  The computer, which decides everything about itself; the assignment, a run over
  its events (`AppuniteEquipment.Contracts.Computers`, "One aggregate with a
  lifecycle, and a run per assignment"); and the demand, a person who needs a
  computer until one is issued to them (`AppuniteEquipment.Contracts.Demands`).
  """

  use Boundary,
    deps: [EhOsContract],
    exports: [{Computers, []}, {Assignments, []}, {Demands, []}]
end
