defmodule GraphLab.StatutoryReporting do
  @moduledoc """
  The implementation of `GraphLab.Contracts.StatutoryReporting`: the report's decision,
  the policy on the clinical close, and the send.
  """

  use Boundary,
    deps: [EhOsContract, GraphLab.Contracts],
    exports: [P1Report, ReportOnClinicalClose, SendP1Report]
end
