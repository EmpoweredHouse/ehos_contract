# The invented billing (`Billing`): one test per scenario of each of its contracts and its
# process module, run against its implementations, and one per example of its values.

defmodule Billing.DomainScenariosTest do
  @moduledoc false
  use EhOsContract.ScenarioCase, domain: Billing.Domain
end

defmodule Billing.SubscriptionsScenariosTest do
  @moduledoc false
  use EhOsContract.ScenarioCase, contract: Billing.Contracts.Subscriptions
end

defmodule Billing.PaymentsScenariosTest do
  @moduledoc false
  use EhOsContract.ScenarioCase, contract: Billing.Contracts.Payments
end

defmodule Billing.MonthScenariosTest do
  @moduledoc false
  use EhOsContract.ScenarioCase, process: Billing.Processes.Month
end
