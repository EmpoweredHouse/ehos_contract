defmodule Taxvision.Contracts do
  @moduledoc """
  Contracts, one per context of the workshop's context map (03 §3; plan, the
  decisions before E9); the run that crosses them is a process module,
  `Taxvision.Processes` (plan DD, P2f, #222). An implementation depends on exactly
  one contract, so a change to one context recompiles that context's
  implementations rather than every one there is.
  """

  use Boundary,
    deps: [EhOsContract],
    exports: [{AccountingMonth, []}, {DocumentIntake, []}, {RegistryWatch, []}]
end
