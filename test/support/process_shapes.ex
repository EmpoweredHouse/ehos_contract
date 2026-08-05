defmodule ProcessShapes do
  @moduledoc """
  **Stanowisko badawcze, nie domena.** Patrz `ProcessShapes.Rig`.

  Własna granica, a nie podczepienie pod `Taxvision`: kształty procesu mają być
  sprawdzone **bez** dostępu do czegokolwiek klienckiego, inaczej dowód byłby
  wart tyle, co dowód przeprowadzony w środku pierwszej domeny.

  Repo bierze się **z konfiguracji**, nie referencją do modułu klienta —
  dokładnie jak w `PNS.Emitter`. Pierwsza wersja wskazywała `Taxvision.Repo`
  wprost i `boundary` ją odrzucił, słusznie: fikstura silnika nie ma prawa
  sięgać do drzewa klienta, choćby po samo repo.
  """

  use Boundary,
    deps: [PNS],
    exports: [Rig, Intake, Matching, Resolution]
end
