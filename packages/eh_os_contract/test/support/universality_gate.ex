defmodule UniversalityGate do
  @moduledoc """
  **An engine fixture, not a client tree.** Everything in it is invented — see
  `UniversalityGate.Next.TreatmentEpisode`.

  Having its own boundary rather than hanging off `Taxvision` matters here: the
  universality gate is meant to prove the DSL works **without** access to anything
  belonging to the client. If this fixture could reach TaxVision's modules, the
  proof would be worth as much as one carried out inside the first domain.
  """

  use Boundary,
    deps: [EhOsContract],
    exports: [
      Next.TreatmentEpisode,
      Domain
    ]
end
