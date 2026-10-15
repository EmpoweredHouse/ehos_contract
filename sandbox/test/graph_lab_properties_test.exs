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
