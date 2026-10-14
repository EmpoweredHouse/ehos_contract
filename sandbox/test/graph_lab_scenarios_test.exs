# The test set for drawing the graph (`GraphLab`): one test per scenario of each of its
# contracts and process modules, run against its implementations, as Rehmed's are.

defmodule GraphLab.SchedulingScenariosTest do
  @moduledoc false
  use EhOsContract.ScenarioCase, contract: GraphLab.Contracts.Scheduling
end

defmodule GraphLab.ClinicalDocumentationScenariosTest do
  @moduledoc false
  use EhOsContract.ScenarioCase, contract: GraphLab.Contracts.ClinicalDocumentation
end

defmodule GraphLab.StatutoryReportingScenariosTest do
  @moduledoc false
  use EhOsContract.ScenarioCase, contract: GraphLab.Contracts.StatutoryReporting
end

defmodule GraphLab.SettlementScenariosTest do
  @moduledoc false
  use EhOsContract.ScenarioCase, contract: GraphLab.Contracts.Settlement
end

defmodule GraphLab.ExternalPayersScenariosTest do
  @moduledoc false
  use EhOsContract.ScenarioCase, contract: GraphLab.Contracts.ExternalPayers
end

defmodule GraphLab.TillScenariosTest do
  @moduledoc false
  use EhOsContract.ScenarioCase, contract: GraphLab.Contracts.Till
end

defmodule GraphLab.PatientMessagingScenariosTest do
  @moduledoc false
  use EhOsContract.ScenarioCase, contract: GraphLab.Contracts.PatientMessaging
end

defmodule GraphLab.ClinicalVisitScenariosTest do
  @moduledoc false
  use EhOsContract.ScenarioCase, process: GraphLab.Processes.ClinicalVisit
end

defmodule GraphLab.VisitSettlementScenariosTest do
  @moduledoc false
  use EhOsContract.ScenarioCase, process: GraphLab.Processes.VisitSettlement
end

defmodule GraphLab.TillDayScenariosTest do
  @moduledoc false
  use EhOsContract.ScenarioCase, process: GraphLab.Processes.TillDay
end

defmodule GraphLab.PatientContactScenariosTest do
  @moduledoc false
  use EhOsContract.ScenarioCase, process: GraphLab.Processes.PatientContact
end
