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
      ContractExamples.run(@example, @rule)
    end
  end

  test "każda reguła ma przynajmniej jeden przykład — brama §18 działa" do
    for rule <- @contract.rules() do
      assert @contract.examples_for(rule.name) != [],
             "reguła #{inspect(rule.name)} bez przykładu przeszła kompilację, a nie powinna"
    end
  end
end
