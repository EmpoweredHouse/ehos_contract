# The test set for drawing the graph (`GraphLab`): each of its aggregates tried on legal
# histories of its contract — every history folds, every command decides within the
# contract, and the settlement's invariants hold as `holds?/2` says. Its boundaries are
# left out, as `EhOsContract.PropertyCase` leaves every boundary out.

defmodule GraphLab.SchedulingPropertiesTest do
  @moduledoc false
  use EhOsContract.PropertyCase, contract: GraphLab.Contracts.Scheduling
end

defmodule GraphLab.ClinicalDocumentationPropertiesTest do
  @moduledoc false
  use EhOsContract.PropertyCase, contract: GraphLab.Contracts.ClinicalDocumentation
end

defmodule GraphLab.StatutoryReportingPropertiesTest do
  @moduledoc false
  use EhOsContract.PropertyCase, contract: GraphLab.Contracts.StatutoryReporting
end

defmodule GraphLab.SettlementPropertiesTest do
  @moduledoc false
  use EhOsContract.PropertyCase, contract: GraphLab.Contracts.Settlement, max_runs: 100
end

defmodule GraphLab.TillPropertiesTest do
  @moduledoc false
  use EhOsContract.PropertyCase, contract: GraphLab.Contracts.Till, max_runs: 100
end

defmodule GraphLab.PatientMessagingPropertiesTest do
  @moduledoc false
  use EhOsContract.PropertyCase, contract: GraphLab.Contracts.PatientMessaging
end

defmodule GraphLab.SettlementWalkTest do
  use ExUnit.Case, async: true

  alias GraphLab.Contracts.Settlement.Commands.{CloseSettlement, RecordPayment}

  # Two payments whose sum is past what money holds match no total: the close is refused
  # as payments that do not sum to it, rather than handing the payment rules a sum their
  # declared type refuses.
  test "payments summing past what money holds do not close the settlement" do
    commands = [
      {%RecordPayment{visit_id: "visit-1", method: :card, amount: 5_332_095_980_733_803_679},
       %{}},
      {%RecordPayment{visit_id: "visit-1", method: :cash, amount: 3_891_287_115_741_377_825},
       %{}},
      {%CloseSettlement{visit_id: "visit-1", total: 10_000}, %{}}
    ]

    assert %{closed_on: nil} =
             EhOsContract.PropertyCase.walk(
               GraphLab.Contracts.Settlement,
               :visit_settlement,
               commands
             )
  end
end
