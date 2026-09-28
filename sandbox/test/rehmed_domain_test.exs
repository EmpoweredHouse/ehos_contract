defmodule Rehmed.DomainTest do
  @moduledoc """
  v2 plan, E3: **a domain module compiles in a consumer, under that consumer's
  strict `boundary` and `--warnings-as-errors`**, and what it compiles to is
  reachable through `EhOsContract.Model`.

  The engine's own tests compile domains from strings. This one is a real `.ex` file
  in a client tree, compiled by `mix compile` like any other, so it also shows the
  consumer's side of the formatter export: `mix format --check-formatted` in the
  gate reads it through `import_deps: [:eh_os_contract]`.
  """

  use ExUnit.Case, async: true

  test "the model names the contexts, relations and actors of the client's context map" do
    model = EhOsContract.Model.fetch(Rehmed.Domain)

    assert %{kind: :domain, name: :rehmed, language: :pl} = model

    assert Enum.map(model.contexts, & &1.name) ==
             [
               :scheduling,
               :clinical_documentation,
               :statutory_reporting,
               :settlement,
               :configuration
             ]

    assert Enum.map(model.actors, & &1.name) == [
             :reception,
             :specialist,
             :manager,
             :p1_integration
           ]

    assert Enum.map(model.values, & &1.name) == [:money, :payment_method]

    assert Enum.map(model.relations, & &1.type) ==
             [
               :partnership,
               :customer_supplier,
               :conformist,
               :conformist,
               :open_host_service,
               :open_host_service
             ]
  end

  test "one Polish word is a different term in each context that uses it" do
    # 30-contexts.md: "Wizyta" is a held slot in scheduling, a clinical encounter in
    # documentation and an amount owed in settlement.
    definitions =
      for context <- EhOsContract.Model.fetch(Rehmed.Domain).contexts,
          %{text: "Wizyta", definition: definition} <- context.terms,
          do: {context.name, definition}

    assert definitions == [
             scheduling: "Zarezerwowany termin z zasobami",
             clinical_documentation: "Spotkanie kliniczne z notatką i kodami",
             settlement: "Należna kwota"
           ]
  end

  test "the formatter keeps options beside a do block without parentheses (v2 §16, D13)" do
    # `mix format --check-formatted` in the gate already holds the whole file. This
    # names the one declaration D13 is about, and formats it with this project's own
    # formatter, the one `import_deps` builds.
    path = "lib/rehmed/domain.ex"
    source = File.read!(path)

    four_arguments =
      ~s|context :scheduling, "Umawianie i zasoby", subdomain: :core, source: "CTX-01" do|

    assert source =~ four_arguments
    {format, _options} = Mix.Tasks.Format.formatter_for_file(path)
    assert format.(source) == source
  end

  test "Values has a type per value, readable from the compiled module" do
    {:ok, types} = Code.Typespec.fetch_types(Rehmed.Domain.Values)
    assert Enum.sort(for {:type, {name, _, _}} <- types, do: name) == [:money, :payment_method]
  end
end
