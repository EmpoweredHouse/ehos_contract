defmodule Taxvision.DocumentIntake do
  @moduledoc """
  What `Taxvision.Contracts.DocumentIntake` (03 §4.3) needs implemented: the format
  of KSeF's number. The inbox decides nothing — the integration records into it —
  so it has no implementation.
  """

  use Boundary,
    deps: [Taxvision.Domain],
    exports: [KsefNumber]
end
