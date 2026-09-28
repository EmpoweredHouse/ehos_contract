defmodule Rehmed.StatutoryReporting do
  @moduledoc """
  The implementation of `Rehmed.Contracts.StatutoryReporting` (`CTX-04`): the
  report's decision, the policy on the clinical close, and the send.
  """

  use Boundary,
    deps: [EhOsContract, Rehmed.Contracts],
    exports: [P1Report, ReportOnClinicalClose, SendP1Report]
end
