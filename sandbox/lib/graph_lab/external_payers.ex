defmodule GraphLab.ExternalPayers do
  @moduledoc """
  The implementation of `GraphLab.Contracts.ExternalPayers`, as
  `Rehmed.ExternalPayers`'s.
  """

  use Boundary, deps: [EhOsContract, GraphLab.Contracts], exports: [PayerPeriod]
end
