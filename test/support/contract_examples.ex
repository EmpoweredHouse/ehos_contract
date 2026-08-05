defmodule ContractExamples do
  @moduledoc """
  Wykonanie jednego `example` z kontraktu. Wspólne dla wszystkich kontraktów,
  bo „przykład jest testem" ma być własnością DSL-a, a nie własnością
  TaxVision — brama uniwersalności sprawdza między innymi to.
  """

  use Boundary, deps: [], exports: []

  import ExUnit.Assertions

  def run(example, rule) do
    {module, function, 1} = rule.function
    {command_name, params} = example.command

    input =
      example.given
      |> Map.put(:command, command_name)
      |> Map.merge(params)

    case example.outcome do
      {:rejected, reason} ->
        assert {:error, ^reason} = apply(module, function, [input])

      {:emits, []} ->
        assert :ok = apply(module, function, [input])

      {:emits, expected} ->
        emissions = apply(module, function, [input])
        assert is_list(emissions), "oczekiwano listy zamiarów, dostałem #{inspect(emissions)}"
        emitted = Enum.map(emissions, & &1.name)

        # **Podciąg, nie równość.** Pierwsza wersja wymagała, żeby przykład
        # wymienił wszystko, co funkcja emituje — więc przykład reguły
        # "bez zgodnej weryfikacji miesiąc się nie otwiera" pinował cztery
        # zdarzenia, z czego trzy nie miały z tą regułą nic wspólnego. Dodanie
        # jednego zdarzenia do przepływu wywalało wszystkie przykłady tej
        # reguły, choć reguła się nie zmieniła. Przy pięćdziesięciu regułach to
        # maszyna do fałszywych alarmów, czyli do wyłączenia testów.
        assert subsequence?(expected, emitted),
               """
               przykład wymaga, żeby wśród wyemitowanych zdarzeń wystąpiły — w tej kolejności:
                 #{inspect(expected)}
               a funkcja wyemitowała:
                 #{inspect(emitted)}
               """
    end
  end

  # Czy `expected` występuje w `emitted` w tej kolejności, niekoniecznie obok siebie.
  defp subsequence?([], _emitted), do: true
  defp subsequence?(_expected, []), do: false
  defp subsequence?([head | tail], [head | rest]), do: subsequence?(tail, rest)
  defp subsequence?(expected, [_ | rest]), do: subsequence?(expected, rest)
end
