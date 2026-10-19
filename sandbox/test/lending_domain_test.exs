defmodule Lending.DomainTest do
  @moduledoc """
  **A domain module compiles in a consumer, under that consumer's strict `boundary` and
  `--warnings-as-errors`**, and what it compiles to is reachable through
  `EhOsContract.Model`.

  The engine's own tests compile domains from strings. This one is a real `.ex` file,
  compiled by `mix compile` like any other, so it also shows the consumer's side of the
  formatter export: `mix format --check-formatted` in the gate reads it through
  `import_deps: [:eh_os_contract]`.
  """

  use ExUnit.Case, async: true

  test "the model names the contexts, the relation, the actors and the values" do
    model = EhOsContract.Model.fetch(Lending.Domain)

    assert %{kind: :domain, name: :lending, language: :en} = model
    assert Enum.map(model.contexts, & &1.name) == [:circulation, :membership]
    assert Enum.map(model.relations, & &1.type) == [:customer_supplier]
    assert Enum.map(model.actors, & &1.name) == [:librarian, :patron]
    assert Enum.map(model.values, & &1.name) == [:money]
  end

  test "every term carries its German translation" do
    translations =
      for context <- EhOsContract.Model.fetch(Lending.Domain).contexts,
          %{text: text, translations: translations} <- context.terms,
          %{language: :de, text: german} <- translations,
          do: {text, german}

    assert translations == [
             {"Copy", "Exemplar"},
             {"Loan", "Ausleihe"},
             {"Member", "Mitglied"},
             {"Fee", "Gebühr"},
             {"Hold", "Vormerkung"},
             {"Membership", "Mitgliedschaft"},
             {"Member", "Mitglied"},
             {"Card", "Ausweis"}
           ]
  end

  test "the formatter keeps options beside a do block without parentheses" do
    # `mix format --check-formatted` in the gate already holds the whole file. This
    # names one declaration with options and a do block, and formats it with this
    # project's own formatter, the one `import_deps` builds.
    path = "lib/lending/domain.ex"
    source = File.read!(path)

    options_and_block =
      ~s|entity :card, "Membership card", context: :membership, identity: :card_id do|

    assert source =~ options_and_block
    {format, _options} = Mix.Tasks.Format.formatter_for_file(path)
    assert format.(source) == source
  end

  test "Values has a type per value, readable from the compiled module" do
    {:ok, types} = Code.Typespec.fetch_types(Lending.Domain.Values)
    assert for({:type, {name, _, _}} <- types, do: name) == [:money]
  end
end
