defmodule GraphLab.ClinicalDocumentation do
  @moduledoc """
  The implementation of `GraphLab.Contracts.ClinicalDocumentation`: the documentation's
  decision, the chase after it, and the visit's note.
  """

  use Boundary,
    deps: [EhOsContract, GraphLab.Contracts],
    exports: [VisitDocumentation, DocumentationChase, VisitNote]
end
