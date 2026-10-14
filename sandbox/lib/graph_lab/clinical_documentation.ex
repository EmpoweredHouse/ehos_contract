defmodule GraphLab.ClinicalDocumentation do
  @moduledoc """
  The implementation of `GraphLab.Contracts.ClinicalDocumentation`, as
  `Rehmed.ClinicalDocumentation`'s.
  """

  use Boundary,
    deps: [EhOsContract, GraphLab.Contracts],
    exports: [VisitDocumentation, DocumentationChase]
end
