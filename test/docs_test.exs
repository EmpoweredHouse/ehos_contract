defmodule PNS.DocsTest do
  @moduledoc """
  `docs/contract.md` opisuje DSL, więc jest **drugim źródłem prawdy o tym samym**
  — a to jest dokładnie ta awaria, którą ten produkt wykrywa u innych. W jeden
  dzień znaleźliśmy cztery takie rozjazdy między rekordem a kodem, w tym przykład
  DSL w notatkach §1 używający typów, których w słowniku nie ma.

  Te testy są mechanizmem, który pozwala temu plikowi istnieć. Trzy rzeczy:

  1. **Przykład z dokumentacji się kompiluje.** Nie jest ilustracją, jest
     fikstórą. Ta sama zasada, którą kontrakt stosuje do reguł, zastosowana do
     własnej dokumentacji.
  2. **Każdy klucz DSL-a jest w dokumencie opisany.** Dopisanie klucza bez
     opisania go wywala test.
  3. **Każda brama z tabeli „co się nie skompiluje" ma test.** Tabela obiecuje
     błąd kompilacji; test dowodzi, że obietnica jest prawdziwa.

  Generowany blok referencji pilnuje się sam — `mix pns.docs --check` w `mix
  check` wywala build, jeśli jest nieaktualny.
  """

  use ExUnit.Case, async: true

  @path "docs/contract.md"

  setup_all do
    {:ok, doc: File.read!(@path)}
  end

  describe "przykład jest fikstórą, nie ilustracją" do
    test "każdy blok kodu z kontraktem w dokumentacji się kompiluje", %{doc: doc} do
      kontrakty = bloki_z_kontraktem(doc)

      assert kontrakty != [],
             "dokumentacja bez ani jednego kompilowalnego przykładu nie jest sprawdzana przez nic"

      for {kod, index} <- Enum.with_index(kontrakty) do
        # Jeśli to rzuci, dokumentacja skłamała o tym, co się kompiluje.
        assert [_ | _] = Code.compile_string(kod),
               "blok ##{index} z #{@path} nie kompiluje się"
      end
    end
  end

  describe "słownik i dokument nie mogą się rozjechać" do
    test "każdy klucz z `PNS.Contract.schema/0` jest w dokumencie wymieniony", %{doc: doc} do
      brakujace =
        for {deklaracja, klucze} <- PNS.Contract.vocabulary(),
            klucz <- klucze,
            not String.contains?(doc, "`#{klucz}`"),
            do: {deklaracja, klucz}

      assert brakujace == [],
             "klucze DSL-a nieopisane w #{@path}: #{inspect(brakujace)}. " <>
               "Dopisanie słowa do DSL bez opisania go zostawia dokument, który kłamie przez pominięcie."
    end

    test "każda deklaracja ma sekcję w referencji", %{doc: doc} do
      for deklaracja <- Map.keys(PNS.Contract.vocabulary()) do
        assert String.contains?(doc, "### `#{deklaracja}`"),
               "brak sekcji referencji dla `#{deklaracja}`"
      end
    end
  end

  describe "tabela bram obiecuje błąd kompilacji" do
    test "liczba wierszy tabeli nie przekracza liczby testów bram", %{doc: doc} do
      # Słabszy warunek niż mapowanie jeden-do-jednego, ale sprawdzalny i łapie
      # przypadek, który naprawdę grozi: dopisanie do tabeli obietnicy, której
      # nikt nie dowiódł.
      obietnice = wiersze_tabeli_bram(doc)
      testy = testy_bram()

      assert obietnice > 0
      assert obietnice <= testy,
             "tabela „co się nie skompiluje” obiecuje #{obietnice} bram, a testów bram jest #{testy}. " <>
               "Obietnica bez testu to zdanie w prozie."
    end
  end

  defp bloki_z_kontraktem(doc) do
    ~r/```elixir\n(.*?)```/s
    |> Regex.scan(doc, capture: :all_but_first)
    |> Enum.map(&List.first/1)
    |> Enum.filter(&String.contains?(&1, "use PNS.Contract"))
  end

  defp wiersze_tabeli_bram(doc) do
    doc
    |> String.split("## What refuses to compile", parts: 2)
    |> List.last()
    |> String.split("\n## ", parts: 2)
    |> List.first()
    |> String.split("\n")
    |> Enum.count(&String.match?(&1, ~r/^\| .* \| .* \|$/))
    # minus nagłówek i separator
    |> Kernel.-(2)
  end

  defp testy_bram do
    "test/compile_gates_test.exs"
    |> File.read!()
    |> then(&Regex.scan(~r/^\s+test "/m, &1))
    |> length()
  end
end
