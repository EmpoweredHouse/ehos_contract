defmodule GraphLab.StatutoryReporting do
  @moduledoc """
  The implementation of `GraphLab.Contracts.StatutoryReporting`, as
  `Rehmed.StatutoryReporting`'s.
  """

  use Boundary,
    deps: [EhOsContract, GraphLab.Contracts],
    exports: [P1Report, ReportOnClinicalClose, SendP1Report]
end
