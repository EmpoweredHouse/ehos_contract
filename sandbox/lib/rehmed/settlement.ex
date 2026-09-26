defmodule Rehmed.Settlement do
  @moduledoc """
  The one piece of Rehmed code in this repository, and it exists for the library
  rather than for the clinic: without a decision, `Rehmed.Contracts.VisitSettlement`
  could not run its scenarios, which are how a contract becomes executable tests.

  Until 26 September 2026 this module was `decide/1`, the function v1's `rule`
  pointed at. In v2 the decision is the implementation of the contract's aggregate,
  `Rehmed.Settlement.VisitSettlement` (v2 §4.5), and this module is only its
  boundary. It is pure: no repo, no schema, no process.
  """

  use Boundary, deps: [EhOsContract, Rehmed.Contracts], exports: [VisitSettlement]
end
