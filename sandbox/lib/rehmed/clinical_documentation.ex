defmodule Rehmed.ClinicalDocumentation do
  @moduledoc """
  The implementation of `Rehmed.Contracts.ClinicalDocumentation` (`CTX-03`): the
  documentation's decision and the chase after it, both pure.
  """

  use Boundary,
    deps: [EhOsContract, Rehmed.Contracts],
    exports: [VisitDocumentation, DocumentationChase]
end
