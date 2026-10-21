defmodule Billing.PropertiesTest do
  @moduledoc """
  The subscription's, the invoice's and the payment's decisions tried on legal histories
  of their contracts: every history folds, and every command decides within the
  contract.
  """

  use EhOsContract.PropertyCase, contract: Billing.Contracts.Subscriptions, max_runs: 100
end

defmodule Billing.PaymentsPropertiesTest do
  @moduledoc false
  use EhOsContract.PropertyCase, contract: Billing.Contracts.Payments, max_runs: 100
end
