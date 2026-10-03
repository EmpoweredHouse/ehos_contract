defmodule AppuniteEquipment.Contracts do
  @moduledoc """
  The computer, which decides everything, and the assignment, a run over three of
  its events (`AppuniteEquipment.Contracts.Computers`, "One aggregate, and a run per
  assignment").
  """

  use Boundary,
    deps: [EhOsContract],
    exports: [{Computers, []}, {Assignments, []}]
end
