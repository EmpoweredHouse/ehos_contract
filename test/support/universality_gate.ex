defmodule UniversalityGate do
  @moduledoc """
  **Fikstura silnika, nie drzewo klienta.** Cała zawartość jest wymyślona —
  patrz `UniversalityGate.TreatmentEpisode`.

  Własna granica, a nie podczepienie pod `Taxvision`, jest tu istotne: brama
  uniwersalności ma dowodzić, że DSL działa **bez** dostępu do czegokolwiek
  klienckiego. Gdyby ta fikstura mogła sięgnąć do modułów TaxVision, dowód
  byłby wart tyle, co dowód przeprowadzony w środku pierwszej domeny.
  """

  use Boundary,
    deps: [PNS],
    exports: [TreatmentEpisode, Eligibility, PayerRegistry, PayerRegistry.Fake]
end
