defmodule EhOsContract.DomainInvariantsTest do
  @moduledoc """
  Plan EL2b: **a value's invariants** — declared with the examples that break and keep
  them (D9), a behaviour the domain generates for them, and the module bound with
  `use Domain, value: :name` that defines one function per invariant (I1, I2).
  """

  use EhOsContract.DslCase, async: false

  alias EhOsContract.{Digest, Model}

  defp domain(name, body) do
    """
    defmodule EhOsContract.DomainInvariantsTest.#{name} do
      use EhOsContract.Domain, name: :clinic, language: :pl

    #{body}
    end
    """
  end

  defp compile_domain(name, body) do
    compile(domain(name, body), "#{Macro.underscore(name)}.ex")
    Module.concat(EhOsContract.DomainInvariantsTest, name)
  end

  defp refuse(name, body),
    do: assert_refused(domain(name, body), "#{Macro.underscore(name)}.ex", "D9")

  @money """
    value :money, :integer, unit: :grosze do
      invariant :not_negative, "Kwota nie jest ujemna", violated_by: [-1], satisfied_by: [0, 15_000]
    end
  """

  describe "the model" do
    test "keeps each invariant with its examples, in declaration order" do
      domain =
        compile_domain("Kept", """
          value :period do
            field :from, :date
            field :to, :date

            invariant :in_order, "Okres kończy się nie wcześniej, niż się zaczyna",
              violated_by: [%{from: "2026-02-01", to: "2026-01-31"}],
              satisfied_by: [%{from: "2026-01-01", to: "2026-01-01"}],
              source: "W2 00:14:10"

            invariant :within_a_year, "Okres trwa najwyżej rok",
              violated_by: [%{from: "2026-01-01", to: "2027-01-02"}],
              satisfied_by: [%{from: "2026-01-01", to: "2026-12-31"}]
          end
        """)

      [period] = Model.fetch(domain).values

      assert [
               %{
                 name: :in_order,
                 label: "Okres kończy się nie wcześniej, niż się zaczyna",
                 violated_by: [%{from: "2026-02-01", to: "2026-01-31"}],
                 satisfied_by: [%{from: "2026-01-01", to: "2026-01-01"}],
                 source: "W2 00:14:10"
               },
               %{name: :within_a_year}
             ] = period.invariants
    end

    test "a value without invariants hashes as it did before values had them" do
      domain = compile_domain("Unmoved", "  value :money, :integer, unit: :grosze\n")
      model = Model.fetch(domain)
      [money] = model.values

      assert money.invariants == []
      assert model.digests["value:money"] == Digest.hash(Map.delete(money, :invariants))
    end

    test "an invariant moves its value's digest, and the order of invariants does not" do
      two = fn name, first, second ->
        compile_domain(name, """
          value :money, :integer do
            #{first}
            #{second}
          end
        """)
        |> Model.fetch()
      end

      a = ~s|invariant :not_negative, "A", violated_by: [-1], satisfied_by: [0]|
      b = ~s|invariant :below_cap, "B", violated_by: [1001], satisfied_by: [1000]|
      bare = Model.fetch(compile_domain("Bare", "  value :money, :integer\n"))

      assert two.("Ab", a, b).digests["value:money"] == two.("Ba", b, a).digests["value:money"]
      refute two.("Ab2", a, b).digests["value:money"] == bare.digests["value:money"]
    end
  end

  describe "the behaviour" do
    test "has one callback per invariant, taking the value, for a value that declares one" do
      domain =
        compile_domain("Behaviour", """
        #{@money}
          value :method, {:enum, [:card, :cash]}
        """)

      behaviour = Model.module_for(domain, :value, :money)
      assert behaviour == Module.concat([domain, Values, Money])
      assert behaviour.behaviour_info(:callbacks) == [not_negative: 1]

      refute Code.ensure_loaded?(Module.concat([domain, Values, Method]))

      assert_raise ArgumentError, ~r/declares no value :method with invariants/, fn ->
        Model.module_for(domain, :value, :method)
      end
    end
  end

  describe "D9" do
    test "an invariant gives both kinds of example, each at least once" do
      refuse("NoViolation", """
        value :money, :integer do
          invariant :not_negative, "Kwota nie jest ujemna", violated_by: [], satisfied_by: [0]
        end
      """) =~ "gives no violated_by: example; give at least one, since each is a test"

      message =
        assert_refused(
          domain("NoSatisfaction", """
            value :money, :integer do
              invariant :not_negative, "Kwota nie jest ujemna", violated_by: [-1]
            end
          """),
          "no_satisfaction.ex",
          "satisfied_by"
        )

      assert message =~ "required"
    end

    test "every example is plain data of the value's type, and none is nil" do
      message =
        refuse("Unfit", """
          value :money, :integer do
            invariant :not_negative, "Kwota nie jest ujemna",
              violated_by: ["-1", nil],
              satisfied_by: [0]
          end

          value :period do
            field :from, :date
            field :to, :date

            invariant :in_order, "W kolejności",
              violated_by: [%{from: ~D[2026-02-01], to: "2026-01-31"}],
              satisfied_by: [%{from: "2026-01-01"}]
          end
        """)

      assert message =~
               "D9: invariant :not_negative of value :money, violated_by: \"-1\" is not an :integer"

      assert message =~ "violated_by: nil is no value; an absent field is never checked"
      assert message =~ "invariant :in_order of value :period, violated_by: :period, field :from"
      assert message =~ "Date is a struct"
      assert message =~ "satisfied_by: :period needs :to"
    end

    test "no example both breaks an invariant and keeps it" do
      assert refuse("Both", """
               value :money, :integer do
                 invariant :not_negative, "Kwota nie jest ujemna",
                   violated_by: [-1, 0],
                   satisfied_by: [0]
               end
             """) =~ "D9: invariant :not_negative of value :money gives 0 in both"
    end

    test "no example that keeps one invariant is given as breaking another" do
      message =
        refuse("Contradicted", """
          value :amount, :integer do
            invariant :not_negative, "Nieujemna", violated_by: [-1], satisfied_by: [0]
            invariant :non_zero, "Niezerowa", violated_by: [0], satisfied_by: [1]
          end

          value :fee, :amount do
            invariant :capped, "Najwyżej tysiąc", violated_by: [1001], satisfied_by: [-1, 1000]
          end

          value :line do
            field :amount, :amount
            invariant :filled, "Wypełniona", violated_by: [%{amount: 1001}], satisfied_by: [%{amount: -1}]
          end
        """)

      assert message =~
               "D9: invariant :not_negative of value :amount gives 0 in satisfied_by:, and invariant " <>
                 ":non_zero of value :amount gives it in violated_by:; a value that keeps one " <>
                 "invariant breaks no other"

      assert message =~
               "invariant :capped of value :fee gives -1 in satisfied_by:, and invariant " <>
                 ":not_negative of value :amount gives what it holds there in violated_by:"

      assert message =~ "invariant :filled of value :line gives %{amount: -1} in satisfied_by:"
      refute message =~ "gives 1000 in satisfied_by:"
    end

    test "no example is given twice, since each names its test" do
      message =
        refuse("Twice", """
          value :money, :integer do
            invariant :not_negative, "Kwota nie jest ujemna",
              violated_by: [-1, -1],
              satisfied_by: [0, 5, 0]
          end
        """)

      assert message =~
               "D9: invariant :not_negative of value :money gives -1 twice in violated_by:"

      assert message =~ "gives 0 twice in satisfied_by:"
    end

    test "an invariant is named once in its value, as a function can be" do
      message =
        refuse("Names", """
          value :money, :integer do
            invariant :not_negative, "A", violated_by: [-1], satisfied_by: [0]
            invariant :not_negative, "B", violated_by: [-2], satisfied_by: [1]
            invariant :NotHuge, "C", violated_by: [10_000_000], satisfied_by: [1]
            invariant :abs, "D", violated_by: [-3], satisfied_by: [2]
            invariant :module_info, "E", violated_by: [-4], satisfied_by: [3]
            invariant :type, "F", violated_by: [-5], satisfied_by: [4]
          end
        """)

      assert message =~ "D9: value :money declares the invariant :not_negative twice"
      assert message =~ "invariant :NotHuge of value :money is not snake_case"

      assert message =~
               "invariant :abs of value :money would define abs/1, which clashes with Kernel.abs/1"

      assert message =~ "would define module_info/1, which every module defines already"
      assert message =~ "invariant :type of value :money is named like a refusal of a field"
    end

    test "points at the invariant" do
      assert_refused(
        domain("Where", """
          value :money, :integer do
            invariant :not_negative, "A", violated_by: [0], satisfied_by: [0]
          end
        """),
        "where.ex",
        "D9",
        5
      )
    end
  end

  describe "the examples, as tests" do
    alias EhOsContract.ScenarioCase

    @percent """
      value :percent, :integer do
        invariant :not_negative, "Nieujemny", violated_by: [-1], satisfied_by: [0, 100]
        invariant :at_most_whole, "Najwyżej całość", violated_by: [101], satisfied_by: [100]
      end
    """

    defp implement(domain, name, body) do
      [{module, _}] =
        compile(
          """
          defmodule EhOsContract.DomainInvariantsTest.#{name} do
            use #{inspect(domain)}, value: :percent
          #{body}
          end
          """,
          "#{Macro.underscore(name)}.ex"
        )

      module
    end

    defp run_all(domain, implementations) do
      for example <- ScenarioCase.examples(domain) do
        try do
          ScenarioCase.run_example(domain, example, implementations)
          {ScenarioCase.describe(example), :passed}
        rescue
          error in ExUnit.AssertionError -> {ScenarioCase.describe(example), error.message}
        end
      end
    end

    test "one per example, each passing against a check that keeps the declaration" do
      domain = compile_domain("Examples", @percent)

      right =
        implement(domain, "RightPercent", """
          @impl true
          def not_negative(p), do: p >= 0
          @impl true
          def at_most_whole(p), do: p <= 100
        """)

      assert run_all(domain, [right]) == [
               {"invariant :not_negative of value :percent: -1 breaks it", :passed},
               {"invariant :not_negative of value :percent: 0 keeps it", :passed},
               {"invariant :not_negative of value :percent: 100 keeps it", :passed},
               {"invariant :at_most_whole of value :percent: 101 breaks it", :passed},
               {"invariant :at_most_whole of value :percent: 100 keeps it", :passed}
             ]
    end

    test "failing a check that lets a breaking example through, or refuses a keeping one" do
      domain = compile_domain("Failing", @percent)

      wrong =
        implement(domain, "WrongPercent", """
          @impl true
          def not_negative(_p), do: true
          @impl true
          def at_most_whole(p), do: p < 100
        """)

      results = Map.new(run_all(domain, [wrong]))

      assert results["invariant :not_negative of value :percent: -1 breaks it"] =~
               "-1 breaks invariant :not_negative of value :percent, and " <>
                 "EhOsContract.DomainInvariantsTest.WrongPercent.not_negative/1 lets it through"

      # 100 keeps :not_negative, and a value of :percent that does breaks :at_most_whole.
      assert results["invariant :not_negative of value :percent: 100 keeps it"] =~
               "100 is given as a value of :percent that keeps :not_negative, and " <>
                 "EhOsContract.DomainInvariantsTest.WrongPercent.at_most_whole/1 answers that it " <>
                 "breaks :at_most_whole"

      assert results["invariant :not_negative of value :percent: 0 keeps it"] == :passed
    end

    test "failing a check that answers neither true nor false, and a value nobody implements" do
      domain = compile_domain("Unsure", @percent)

      unsure =
        implement(domain, "UnsurePercent", """
          @impl true
          def not_negative(_p), do: :maybe
          @impl true
          def at_most_whole(_p), do: true
        """)

      [{_, message} | _] = run_all(domain, [unsure])

      assert message =~
               "not_negative/1 answered :maybe; the check of an invariant answers true or false"

      [{_, message} | _] = run_all(domain, [])
      assert message =~ "no module implements value :percent of #{inspect(domain)}"
    end
  end

  describe "binding an implementation" do
    test "defines one function per invariant, and compiles without a warning" do
      domain = compile_domain("Bound", @money)

      {_, diagnostics} =
        Code.with_diagnostics(fn ->
          compile(
            """
            defmodule EhOsContract.DomainInvariantsTest.Money do
              use #{inspect(domain)}, value: :money

              @impl true
              def not_negative(amount), do: amount >= 0
            end
            """,
            "money.ex"
          )
        end)

      assert diagnostics == []
      implementation = Module.concat(EhOsContract.DomainInvariantsTest, Money)

      assert %{contract: ^domain, kind: :value, name: :money} =
               implementation.__eh_os_implementation__()

      assert implementation.not_negative(0)
    end

    test "I1: names a value that declares invariants, and nothing a contract has" do
      domain =
        compile_domain("Named", """
        #{@money}
          value :method, {:enum, [:card, :cash]}
        """)

      use_line = fn file, opts ->
        refusal(
          """
          defmodule EhOsContract.DomainInvariantsTest.#{Macro.camelize(file)} do
            use #{inspect(domain)}, #{opts}
          end
          """,
          "#{file}.ex"
        ).message
      end

      assert use_line.("mony", "value: :mony") =~
               "I1: use #{inspect(domain)}: there is no value :mony; did you mean :money?"

      assert use_line.("method", "value: :method") =~
               "value :method declares no invariant, so there is nothing to implement"

      assert use_line.("unit", "aggregate: :money") =~
               "I1: use #{inspect(domain)} takes one of [:value]; [:aggregate] is not among them"

      assert use_line.("nothing", "[]") =~ "write `use #{inspect(domain)}, value: :name`"
    end

    test "I2: every invariant has its function, and the error shows the clause" do
      domain = compile_domain("Unchecked", @money)

      assert_refused(
        """
        defmodule EhOsContract.DomainInvariantsTest.Unchecked.Money do
          use #{inspect(domain)}, value: :money
        end
        """,
        "unchecked_money.ex",
        "I2: EhOsContract.DomainInvariantsTest.Unchecked.Money does not define not_negative/1, " <>
          "which value :money of #{inspect(domain)} expects. Add:\n\n" <>
          "    @impl true\n    def not_negative(money) do",
        2
      )
    end

    test "I7: emit/1 does not belong in a value's check" do
      domain = compile_domain("Emitting", @money)

      assert_refused(
        """
        defmodule EhOsContract.DomainInvariantsTest.Emitting.Money do
          use #{inspect(domain)}, value: :money

          @impl true
          def not_negative(amount), do: emit(%{amount: amount})
        end
        """,
        "emitting_money.ex",
        "I7: emit/1 belongs in an aggregate or a dcb, and this module implements value :money"
      )
    end
  end
end
