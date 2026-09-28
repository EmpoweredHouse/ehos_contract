defmodule Taxvision.RegistryWatch do
  @moduledoc """
  The implementation of `Taxvision.Contracts.RegistryWatch` (03 §4.2): the company's
  decision, which is pure, the registries asked by an effect outside the
  transaction, the comparison their answer goes to, and the check on the first of
  the month.

  Until 28 September 2026 the check was `Taxvision.RegistryCheck.decide/1`, the
  function v1's `rule` pointed at, fed by `Taxvision.Api` with the registries' answer.
  """

  use Boundary,
    deps: [EhOsContract, Taxvision.Contracts, Taxvision.Adapters, Taxvision.Periods],
    exports: [Client, LookUpRegistries, CompareWithRegistries, MonthlyRegistryCheck]
end
