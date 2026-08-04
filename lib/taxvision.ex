defmodule Taxvision do
  @moduledoc """
  Aplikacja klienta. To, co jest specyficzne dla TaxVision — a wszystko, co nie
  jest, ląduje w `lib/pns/`. Ta jedna reguła jest całą dyscypliną tego
  prototypu (notatki §15, krok 1).

  Topologia granic jest tu treścią, nie ozdobą. Każdy moduł procesowy jest
  **osobną granicą** i rodzeństwem pozostałych, więc dostęp do cudzych tabel
  wymaga jawnego `deps` — którego nikt nie wpisze przez przypadek. `boundary`
  odrzucił pierwszą wersję, w której `Taxvision` zależał od własnych dzieci, i
  miał rację: to była hierarchia udająca granicę.
  """

  use Boundary, deps: [PNS], exports: []
end
