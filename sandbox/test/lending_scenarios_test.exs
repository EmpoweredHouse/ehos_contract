# The library (`Lending`): one test per scenario of each of its contracts and process
# modules, run against its implementations.

defmodule Lending.MembershipScenariosTest do
  @moduledoc false
  use EhOsContract.ScenarioCase, contract: Lending.Contracts.Membership
end

defmodule Lending.CirculationScenariosTest do
  @moduledoc false
  use EhOsContract.ScenarioCase, contract: Lending.Contracts.Circulation
end

defmodule Lending.LoanProcessScenariosTest do
  @moduledoc false
  use EhOsContract.ScenarioCase, process: Lending.Processes.Loan
end

defmodule Lending.LateFeeProcessScenariosTest do
  @moduledoc false
  use EhOsContract.ScenarioCase, process: Lending.Processes.LateFee
end
