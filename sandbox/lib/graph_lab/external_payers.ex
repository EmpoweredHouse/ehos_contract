defmodule GraphLab.ExternalPayers do
  @moduledoc """
  The implementation of `GraphLab.Contracts.ExternalPayers`: the decision over one payer's
  period.
  """

  use Boundary, deps: [EhOsContract, GraphLab.Contracts], exports: [PayerPeriod]
end
