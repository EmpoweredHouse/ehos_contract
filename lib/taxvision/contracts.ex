defmodule Taxvision.Contracts do
  @moduledoc """
  Kontrakty, po jednym na proces (notatki §1).

  Jednostką podziału jest **proces**: jest już pierwszoklasowy, jest jednostką
  nawigacji dashboardu i jest tym, co produkuje warsztat. Handler zależy
  kompilacyjnie od dokładnie jednego kontraktu, więc dodanie zdarzenia
  rekompiluje handlery tego jednego procesu, a nie wszystkie.
  """

  use Boundary, deps: [PNS], exports: [AccountingMonth]
end
