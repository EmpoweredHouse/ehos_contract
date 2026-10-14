defmodule GraphLab.Contracts do
  @moduledoc """
  The test set's contracts (`GraphLab`): one per context, but settlement's, which has two
  — the visit settlement and the till.
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
