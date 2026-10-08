defmodule Taxvision.AccountingMonthScenariosTest do
  @moduledoc "One test per scenario of `Taxvision.Processes.AccountingMonth`: its promise judged."

  use EhOsContract.ScenarioCase, process: Taxvision.Processes.AccountingMonth
end
