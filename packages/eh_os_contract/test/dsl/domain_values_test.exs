defmodule EhOsContract.DomainValuesTest do
  @moduledoc """
  v2 plan, E3: **a domain generates `Values`, one type per value**, which contracts
  will refer to as remote types (v2 §5).
  """

  use EhOsContract.DslCase, async: false

  describe "the generated Values module" do
    # Compiled from a string so the test holds the module's binary. Typespecs are read
    # from its debug chunk, which `compile/2` switches on.
    defp types_of(compiled, suffix) do
      {_, binary} =
        Enum.find(compiled, fn {module, _} -> String.ends_with?(inspect(module), suffix) end)

      {:ok, types} = Code.Typespec.fetch_types(binary)

      Map.new(types, fn {:type, {name, _, _} = type} ->
        {name, type |> Code.Typespec.type_to_quoted() |> Macro.to_string()}
      end)
    end

    defp typed do
      compile("""
      defmodule EhOsContract.DomainTest.Typed do
        use EhOsContract.Domain, name: :clinic, language: :pl

        value :money, :integer, unit: :cents
        value :method, {:enum, [card: "Card", cash: "Cash"]}
        value :codes, {:list, :id}

        value :line do
          field :amount, :money
          field :paid_on, :date, optional: true
          field :methods, {:list, :method}
        end
      end
      """)
    end

    test "has one type per value, in the shape the value declares" do
      assert types_of(typed(), ".Values") == %{
               money: "money() :: integer()",
               method: "method() :: :card | :cash",
               codes: "codes() :: [String.t()]",
               line: "line() :: EhOsContract.DomainTest.Typed.Values.Line.t()"
             }
    end

    # #486: a value made of fields is a struct of its own, its required fields enforced.
    test "gives a value made of fields a struct, its required fields enforced" do
      compiled = typed()
      line = EhOsContract.DomainTest.Typed.Values.Line

      %{t: t} = types_of(compiled, ".Values.Line")
      assert t =~ "t() :: %EhOsContract.DomainTest.Typed.Values.Line{"
      assert t =~ "amount: EhOsContract.DomainTest.Typed.Values.money(),"
      assert t =~ "methods: [EhOsContract.DomainTest.Typed.Values.method()]"
      assert t =~ "paid_on: Date.t() | nil"

      assert %{amount: 1, paid_on: nil, methods: []} = struct!(line, amount: 1, methods: [])

      assert_raise ArgumentError,
                   ~r/the following keys must also be given.*\[:amount, :methods\]/s,
                   fn ->
                     struct!(line, [])
                   end

      assert EhOsContract.Model.module_for(EhOsContract.DomainTest.Typed, :value, :line) == line
    end
  end

  describe "members/1" do
    # Compiled once: each test asks the same domain.
    setup do
      domain = EhOsContract.DomainTest.Members

      unless Code.ensure_loaded?(domain) do
        compile("""
        defmodule EhOsContract.DomainTest.Members do
          use EhOsContract.Domain, name: :clinic, language: :pl

          value :method, {:enum, [card: "Karta", cash: "Gotówka"]}
          value :refund_method, :method
          value :priority, {:enum, [:low, :high]}
          value :money, :integer, unit: :cents
        end
        """)
      end

      %{domain: domain}
    end

    test "lists an enum's members in the order declared, each with its label", %{domain: domain} do
      assert domain.members(:method) == [card: "Karta", cash: "Gotówka"]
      assert domain.members(:priority) == [low: nil, high: nil]
    end

    test "follows a value named after an enum to its members", %{domain: domain} do
      assert domain.members(:refund_method) == [card: "Karta", cash: "Gotówka"]
    end

    test "refuses a value that is not an enum, or no value at all", %{domain: domain} do
      for name <- [:money, :nothing] do
        assert_raise ArgumentError,
                     ~r/is no enum value of EhOsContract.DomainTest.Members; its enum values are \[:method, :priority, :refund_method\]/,
                     fn -> domain.members(name) end
      end
    end
  end
end
