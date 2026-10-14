defmodule GraphLab.Contracts do
  @moduledoc """
  The test set's contracts (`GraphLab`): Rehmed's five, copied, and two added — the
  till, a second contract in settlement's context, and patient messaging.
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
