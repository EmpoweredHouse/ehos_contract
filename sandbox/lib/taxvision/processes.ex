defmodule Taxvision.Processes do
  @moduledoc """
  Runs that cross TaxVision's contracts, each a process module of its own (plan DD,
  P2f, #222). A process module names its domain and the contracts it includes
  without a compile dependency on them, and nothing calls it: dispatch finds it in
  the running binary.
  """

  use Boundary, deps: [EhOsContract, Taxvision.Contracts], exports: []
end
