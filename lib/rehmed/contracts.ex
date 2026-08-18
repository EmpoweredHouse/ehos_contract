defmodule Rehmed.Contracts do
  @moduledoc """
  Contracts, one per process — the same division as `Taxvision.Contracts` and for
  the same reason (notes §1): a handler depends on exactly one contract, so adding
  an event recompiles that process's handlers rather than every handler there is.

  Rehmed has no handlers here yet. The division is kept anyway, because the point
  at which it starts to matter is the point at which changing it is expensive.
  """

  use Boundary, deps: [PNS], exports: [ClinicalVisit]
end
