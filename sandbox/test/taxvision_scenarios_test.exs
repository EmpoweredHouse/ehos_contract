defmodule Taxvision.RegistryWatchScenariosTest do
  @moduledoc """
  One test per scenario of `Taxvision.Contracts.RegistryWatch`, run against its
  implementations: the company's decision, the comparison, the monthly timer.
  """

  use EhOsContract.ScenarioCase, contract: Taxvision.Contracts.RegistryWatch
end

defmodule Taxvision.AccountingMonthScenariosTest do
  @moduledoc """
  One test per scenario of `Taxvision.Contracts.AccountingMonth`: the month's
  boundary over Registry Watch's verdicts, and the policy that opens it.
  """

  use EhOsContract.ScenarioCase, contract: Taxvision.Contracts.AccountingMonth
end

defmodule Taxvision.DomainValuesTest do
  @moduledoc """
  One test per example of `Taxvision.Domain`'s value invariants: "2026-07" names a
  period, "2026-7" and "2026-13" do not (plan, the decisions before E9c).
  """

  use EhOsContract.ScenarioCase, domain: Taxvision.Domain
end
