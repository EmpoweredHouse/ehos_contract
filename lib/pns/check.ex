defmodule PNS.Check do
  @moduledoc """
  Sprawdzenia **statyczne**: kontrakt przeciw binarce, bez ani jednego zapytania
  do logu.

  Plan produktowy rozdziela dwie połowy weryfikacji i to rozdzielenie ma
  konsekwencję dla kodu: ta połowa należy do CI, jest tania i natychmiastowa, i
  **nie potrzebuje interfejsu**. Druga połowa, behawioralna, mieszka w
  `PNS.Conformance` i czyta log.

  Logika przeniesiona tutaj z zadania mixa, bo tam była funkcją prywatną — czyli
  **logiką bez testu**. Sprawdzenie, którego nikt nie sprawdza, cicho przestaje
  działać, a to jest akurat sprawdzenie, na którym stoi trigger przeglądu ADR §15.
  Reszta `mix pns.check` powinna pójść tą samą drogą; zapisane w `PLAN.md`.
  """

  @doc """
  Krawędzie wsteczne: moduł, który **subskrybuje zdarzenie z późniejszej fazy**
  niż ta, do której sam publikuje.

  To jest sygnatura wyciekającej kompensacji i wprost nazwany trigger przeglądu
  z ADR §15: jedna krawędź wsteczna jest normalna, rosnąca liczba znaczy, że
  decyzja „procesy obserwowane, nie kierowane" się nie sprawdza.

  Liczone **po fazach, nie po pozycji zdarzenia w liście**: wewnątrz fazy
  kontrakt nie twierdzi nic o kolejności, więc dwa zdarzenia tej samej fazy
  nigdy nie są krawędzią wsteczną. Wersja licząca po pozycji dawała fałszywe
  alarmy dokładnie tam, gdzie warsztat mówi o równoległości.
  """
  def backward_edges do
    stage_of = stage_index()

    PNS.Registry.handlers()
    |> Enum.group_by(& &1.module)
    |> Enum.flat_map(fn {module, handlers} ->
      subscribed = for h <- handlers, pos = stage_of[h.event], do: pos
      published = for h <- handlers, e <- h.publishes, pos = stage_of[e], do: pos

      for {process, sub_index, sub_stage} <- subscribed,
          {^process, pub_index, pub_stage} <- published,
          sub_index > pub_index do
        %{module: module, process: process, publishes_in: pub_stage, subscribes_in: sub_stage}
      end
    end)
    |> Enum.sort_by(&{to_string(&1.module), to_string(&1.process)})
  end

  # Faza zdarzenia jest na zdarzeniu, a proces trzyma tylko porządek faz — więc
  # pozycję liczy się indeksem fazy w tym porządku.
  defp stage_index do
    for event <- PNS.Registry.declared_events(),
        process = event.process && event.contract.process(event.process),
        index = Enum.find_index(process.stages, &(&1 == event.stage)),
        into: %{} do
      {event.name, {process.name, index, event.stage}}
    end
  end
end
