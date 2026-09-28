defmodule Taxvision.Contracts do
  @moduledoc """
  Contracts, one per context of the workshop's context map (03 §3), each with its
  one process (plan, the decisions before E9): an implementation depends on exactly
  one contract, so a change to one context recompiles that context's
  implementations rather than every one there is.
  """

  use Boundary, deps: [EhOsContract], exports: [{AccountingMonth, []}, {RegistryWatch, []}]
end
