defmodule PNS.Duration do
  @moduledoc """
  Jednostki czasu DSL-a — **jedno źródło prawdy dla bramy i dla arytmetyki.**

  Istnieje z powodu konkretnej awarii. `within: {1, :month}` przechodziło
  kompilację, bo brama nie miała listy dozwolonych jednostek, i wywalało się
  dopiero **w runtime**, przy ocenie assercji, u klienta. Klasyczny kształt
  dryfu: DSL przyjmował słowo, którego mechanizm nie umiał policzyć.

  Niewidoczne było dlatego, że oba nasze kontrakty liczą w dniach — TaxVision
  `{2, :day}`, a fikstura bramy uniwersalności `{3, :day}` i `{90, :day}`.
  Pisząc ten drugi, bezrefleksyjnie skopiowałem nawyk pierwszego: dla epizodu
  leczenia `{3, :month}` jest naturalniejsze niż 90 dni. Brama uniwersalności
  przepuściła nawyk, bo sprawdza słownik, nie mechanizmy.

  **Jednostek kalendarzowych tu nie ma i nie będzie po cichu.** „Miesiąc" nie
  ma stałej długości, więc przesuwanie o miesiąc wymaga arytmetyki kalendarza i
  rozstrzygnięcia, czym jest miesiąc po 31 stycznia. To jest decyzja, nie detal
  implementacyjny — dopóki nie zapadnie, `within` przyjmuje wyłącznie jednostki
  o stałej długości, a kontrakt z `:month` **nie kompiluje się**.

  `cadence: {1, :month}` to inna sprawa i pozostaje legalne: kadencja mówi, jak
  często instancja jest należna, i nikt jej dziś nie liczy. Kiedy zacznie
  liczyć — monitor zaległych procesów — to samo pytanie o kalendarz wróci tutaj.
  """

  @seconds %{second: 1, minute: 60, hour: 3600, day: 86_400}

  @doc "Jednostki, które da się przeliczyć na sekundy bez kalendarza."
  def units, do: Map.keys(@seconds)

  @doc "Przesunięcie momentu o czas trwania. Log jest w UTC, więc dzień to 86 400 sekund."
  def shift(%DateTime{} = at, {n, unit}) do
    case Map.fetch(@seconds, unit) do
      {:ok, s} -> DateTime.add(at, n * s, :second)
      :error -> raise ArgumentError, message(unit)
    end
  end

  @doc false
  def message(unit) do
    "nieobsługiwana jednostka czasu #{inspect(unit)}. Dozwolone: #{inspect(units())}. " <>
      "Jednostki kalendarzowe wymagają arytmetyki kalendarza i rozstrzygnięcia, czym jest " <>
      "miesiąc po 31 stycznia — a to jest decyzja, nie detal implementacyjny."
  end
end
