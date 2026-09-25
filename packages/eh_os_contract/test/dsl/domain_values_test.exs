defmodule EhOsContract.DomainValuesTest do
  @moduledoc """
  v2 plan, E3: **a domain generates `Values`, one type per value**, which contracts
  will refer to as remote types (v2 §5).
  """

  use EhOsContract.DslCase, async: false

  describe "the generated Values module" do
    # Compiled from a string so the test holds the module's binary. Typespecs are read
    # from its debug chunk, which `compile/2` switches on.
    defp types_of(source) do
      compiled = compile(source)

      {_, binary} =
        Enum.find(compiled, fn {module, _} -> String.ends_with?(inspect(module), ".Values") end)

      {:ok, types} = Code.Typespec.fetch_types(binary)

      Map.new(types, fn {:type, {name, _, _} = type} ->
        {name, type |> Code.Typespec.type_to_quoted() |> Macro.to_string()}
      end)
    end

    test "has one type per value, in the shape the value declares" do
      types =
        types_of("""
        defmodule EhOsContract.DomainTest.Typed do
          use EhOsContract.Domain, name: :clinic, language: :pl

          value :money, :integer, unit: :grosze
          value :method, {:enum, [card: "Karta", cash: "Gotówka"]}
          value :codes, {:list, :id}

          value :line do
            field :amount, :money
            field :paid_on, :date, optional: true
            field :methods, {:list, :method}
          end
        end
        """)

      assert types == %{
               money: "money() :: integer()",
               method: "method() :: :card | :cash",
               codes: "codes() :: [String.t()]",
               line: "line() :: %{amount: money(), paid_on: Date.t() | nil, methods: [method()]}"
             }
    end
  end
end
