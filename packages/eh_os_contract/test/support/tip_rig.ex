defmodule TipRig do
  @moduledoc """
  **An engine fixture, and invented.** A till whose amount and tip each declare a rule
  named `:positive`, so a command refused for its data is told by the field whose data
  breaks it, not by the name alone (issue #458). No workshop stands behind it.
  """

  use Boundary, deps: [EhOsContract], exports: [Domain, Till]
end
