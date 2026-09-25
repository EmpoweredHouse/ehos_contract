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
  end

  test "Values has a type per value, readable from the compiled module" do
    {:ok, types} = Code.Typespec.fetch_types(Rehmed.Domain.Values)
    assert Enum.sort(for {:type, {name, _, _}} <- types, do: name) == [:money, :payment_method]
  end
end
