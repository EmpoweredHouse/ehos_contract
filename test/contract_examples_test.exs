defmodule Taxvision.ContractExamplesTest do
  @moduledoc """
  **Przykład z kontraktu JEST testem** (ADR §18, notatki §6).

  Nie ma tu ani jednego napisanego ręcznie przypadku. Testy poniżej są
  generowane z deklaracji `example` w czasie kompilacji tego pliku — więc gdy
  process owner poprawi przykład w kontrakcie, poprawia się test, a nie jego
  opis.

  To jest też miejsce, w którym §18 okazuje się słabszy, niż brzmi, i warto to
  zapisać: kontrakt trzyma **MFA, nie capture**, żeby nie zależeć od domeny w
  czasie kompilacji. Skutek jest taki, że rozwiązanie funkcji następuje w
  runtime testu, a nie przy kompilacji kontraktu. Brama "reguła bez przykładu
  się nie kompiluje" jest prawdziwa; "przykład jest testem" jest prawdziwe
  dopiero z tym generatorem. Rekord twierdzi jedno, dowozi półtora.
  """

  use ExUnit.Case, async: true

  @contract Taxvision.Contracts.AccountingMonth

  for {example, index} <- Enum.with_index(@contract.examples()) do
    @example example
    @rule @contract.rule(example.rule)

    test "#{example.rule}: #{example.description} (##{index})" do
      # Przekazane jako argument, nie rozwinięte w ciele testu: literał w `case`
      # pozwalałby typecheckerowi uznać pozostałe gałęzie za nieosiągalne i
      # zasypać wyjście ostrzeżeniami.
      run_example(@example, @rule)
    end
  end

  defp run_example(example, rule) do
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

  test "każda reguła ma przynajmniej jeden przykład — brama §18 działa" do
    for rule <- @contract.rules() do
      assert @contract.examples_for(rule.name) != [],
             "reguła #{inspect(rule.name)} bez przykładu przeszła kompilację, a nie powinna"
    end
  end
end
