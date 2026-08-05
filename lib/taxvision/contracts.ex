defmodule Taxvision.Contracts do
  @moduledoc """
  Contracts, one per process (notes §1).

  The unit of division is the **process**: it is already first-class, it is the
  dashboard's navigation unit, and it is what the workshop produces. A handler
  has a compile dependency on exactly one contract, so adding an event recompiles
  the handlers of that one process rather than all of them.
  """

  use Boundary, deps: [PNS], exports: [AccountingMonth]
end
