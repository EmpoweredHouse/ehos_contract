defmodule Rehmed.ExternalPayers do
  @moduledoc """
  The implementation of `Rehmed.Contracts.ExternalPayers` (`CTX-06`): the decision
  over one payer's period, which is pure.
  """

  use Boundary, deps: [EhOsContract, Rehmed.Contracts], exports: [PayerPeriod]
end
