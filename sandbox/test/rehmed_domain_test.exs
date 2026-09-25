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

  test "the model names what v2 §4.5 declares, in declaration order" do
    model = EhOsContract.Model.fetch(Rehmed.Domain)

    assert %{kind: :domain, name: :rehmed, language: :pl} = model
    assert Enum.map(model.contexts, & &1.name) == [:scheduling, :settlement]
    assert Enum.map(model.actors, & &1.name) == [:reception, :specialist, :manager]
    assert Enum.map(model.values, & &1.name) == [:money, :payment_method]

    assert [%{type: :customer_supplier, upstream: :scheduling, downstream: :settlement}] =
             model.relations

    assert [%{terms: [%{text: "Zrealizowana", source: "AGG-01, E-51"}]}, %{terms: []}] =
             model.contexts
  end

  test "the formatter keeps options beside a do block without parentheses (v2 §16, D13)" do
    # `mix format --check-formatted` in the gate already holds the whole file. This
    # names the one declaration D13 is about, and formats it with this project's own
    # formatter, the one `import_deps` builds.
    path = "lib/rehmed/domain.ex"
    source = File.read!(path)
    four_arguments = ~s|context :scheduling, "Umawianie i zasoby", subdomain: :core do|

    assert source =~ four_arguments
    {format, _options} = Mix.Tasks.Format.formatter_for_file(path)
    assert format.(source) == source
  end

  test "Values has a type per value, readable from the compiled module" do
    {:ok, types} = Code.Typespec.fetch_types(Rehmed.Domain.Values)
    assert Enum.sort(for {:type, {name, _, _}} <- types, do: name) == [:money, :payment_method]
  end
end
