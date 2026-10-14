defmodule GraphLab.ClinicalDocumentation do
  @moduledoc """
  The implementation of `GraphLab.Contracts.ClinicalDocumentation`: the documentation's
  decision and the chase after it.
  """

  use Boundary,
    deps: [EhOsContract, GraphLab.Contracts],
    exports: [VisitDocumentation, DocumentationChase]
end
