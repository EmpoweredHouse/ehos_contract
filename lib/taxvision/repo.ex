defmodule Taxvision.Repo do
  @moduledoc """
  Jedno Postgres, jedna transakcja (ADR §5-6).

  Tu leży też szkielet **odłożonego** checka własności danych. Decyzja 008
  odkłada wymuszanie granic z CI na runtime, a przegląd postawił warunek:
  odroczenie jest bezpieczne tylko, jeśli check da się dopisać później.

  Sprawdzone 4 sierpnia na Ecto 3.14.1: da się. `prepare_query/3` dostaje cały
  `%Ecto.Query{}` przed wykonaniem, więc wszystkie dotknięte tabele wychodzą
  strukturalnie z `from` i `joins` — bez parsowania SQL-a. Retrofit to
  nadpisanie jednego callbacku, nie zmiana tego, jak moduły sięgają do repo.

  Ograniczenie, które trzeba znać: hook **nie** odpala się dla
  `insert/2`, `update/2`, `delete/2` na changesecie ani dla surowego SQL-a.
  Pierwsze wymaga nazwania schematu innego modułu, więc widzi to `boundary` w
  czasie kompilacji. Drugie jest jedynym prawdziwie niewidocznym wejściem — i
  dokładnie tym przypadkiem, który przegląd odłożył argumentem, że modele
  generują idiomatyczny Ecto, nie SQL w stringach.
  """

  use Boundary, deps: [], exports: []
  use Ecto.Repo, otp_app: :pns_prototype, adapter: Ecto.Adapters.Postgres

  @impl true
  def prepare_query(_operation, query, opts) do
    if Process.get(:pns_trace_tables) do
      Process.put(:pns_touched_tables, tables(query) ++ (Process.get(:pns_touched_tables) || []))
    end

    {query, opts}
  end

  @doc """
  Tabele dotknięte przez zapytanie. Pułapka, która cicho psuje ten check:
  nazwa tabeli joina nie siedzi w `source` — join zwraca `{nil, ModulSchematu}`,
  więc bez `__schema__(:source)` join wygląda na `nil` i check milczy właśnie
  tam, gdzie ma krzyczeć.
  """
  def tables(%Ecto.Query{} = query) do
    [query.from.source | Enum.map(query.joins, & &1.source)]
    |> Enum.map(&source_to_table/1)
    |> Enum.reject(&is_nil/1)
  end

  defp source_to_table({nil, module}) when is_atom(module) and not is_nil(module),
    do: module.__schema__(:source)

  defp source_to_table({table, _module}) when is_binary(table), do: table
  defp source_to_table(%Ecto.SubQuery{query: query}), do: tables(query)
  defp source_to_table(_), do: nil
end
