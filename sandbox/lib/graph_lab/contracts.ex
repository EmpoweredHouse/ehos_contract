defmodule GraphLab.Contracts do
  @moduledoc """
  The test set's contracts (`GraphLab`): seven, in six of the domain's seven contexts —
  settlement has two, the visit settlement and the till, and configuration none.
  """

  use Boundary,
    deps: [EhOsContract],
    exports: [
      {ClinicalDocumentation, []},
      {ExternalPayers, []},
      {PatientMessaging, []},
      {Scheduling, []},
      {Settlement, []},
      {StatutoryReporting, []},
      {Till, []}
    ]
end
