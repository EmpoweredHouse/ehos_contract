defmodule UniversalityGate do
  @moduledoc """
  **An engine fixture, not a client tree.** Everything in it is invented — see
  `UniversalityGate.TreatmentEpisode`.

  Having its own boundary rather than hanging off a client's tree matters here: the
  universality gate is meant to prove the DSL works **without** access to anything
  belonging to a client. If this fixture could reach a client's modules, the
  proof would be worth as much as one carried out inside the first domain.
  """

  use Boundary,
    deps: [EhOsContract],
    exports: [
      TreatmentEpisode,
      Domain
    ]
end
