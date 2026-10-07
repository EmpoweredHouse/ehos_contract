defmodule Rehmed.Contracts do
  @moduledoc """
  Contracts, one per context of the client's context map (plan, the decisions before
  E9); the runs that cross them are process modules, `Rehmed.Processes` (plan DD, P2f,
  #222). An implementation depends on exactly one
  contract, so a change to one context recompiles that context's implementations
  rather than every one there is.
  """

  use Boundary,
    deps: [EhOsContract],
    exports: [
      {ClinicalDocumentation, []},
      {ExternalPayers, []},
      {Scheduling, []},
      {Settlement, []},
      {StatutoryReporting, []}
    ]
end
