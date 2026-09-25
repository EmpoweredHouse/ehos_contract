defmodule EhOsContract.DomainRulesTest do
  @moduledoc """
  v2 plan, E3: **what a domain module refuses to compile, and where the refusal
  points.**

  Each refusal is a `Spark.Error.DslError` whose message names the problem and the
  file and line of the declaration at fault. That second half is a property of
  Spark this stage has to confirm before E4 builds on it. Each rule has a control
  beside it that compiles.
  """

  use EhOsContract.DslCase, async: false

  defp domain(name, body) do
    """
    defmodule EhOsContract.DomainRulesTest.#{name} do
      use EhOsContract.Domain, name: :clinic, language: :pl

    #{body}
    end
    """
  end

  defp refused(name, body) do
    error = compile_error(domain(name, body), "#{Macro.underscore(name)}.ex")
    Exception.message(error)
  end

  defp compiles(name, body) do
    assert [{_, _}] = Code.compile_string(domain(name, body))
  end

  describe "D1: names are unique per kind" do
    test "two contexts of one name are refused at the second" do
      message =
        refused("TwoContexts", """
          context :settlement, "Rozliczenia", subdomain: :supporting
          context :settlement, "Rozliczenia 2", subdomain: :supporting
        """)

      assert message =~ "D1: two contexts are named :settlement (two_contexts.ex:5)"
    end

    test "every kind is checked, and every violation is reported at once" do
      message =
        refused("EveryKind", """
          actor :reception, :human, "Recepcja"
          actor :reception, :human, "Recepcja"
          subject :patient, "Pacjent"
          subject :patient, "Pacjent"
          value :money, :integer
          value :money, :integer
          external :registry, "Rejestr", direction: :outbound
          external :registry, "Rejestr", direction: :outbound
        """)

      assert message =~ "two actors are named :reception (every_kind.ex:5)"
      assert message =~ "two subjects are named :patient (every_kind.ex:7)"
      assert message =~ "two values are named :money (every_kind.ex:9)"
      assert message =~ "two externals are named :registry (every_kind.ex:11)"
    end

    test "a term defined twice in one context is refused" do
      message =
        refused("TwoTerms", """
          context :settlement, "Rozliczenia" do
            subdomain :supporting
            term "Wizyta", definition: "Spotkanie"
            term "Wizyta", definition: "Inne spotkanie"
          end
        """)

      assert message =~
               ~s|D1: context :settlement defines the term "Wizyta" twice (two_terms.ex:7)|
    end

    test "the control: one name per kind, and one name reused across kinds, compile" do
      compiles("UniqueNames", """
        context :settlement, "Rozliczenia", subdomain: :supporting
        actor :settlement, :system, "Rozliczenia"
        value :money, :integer
        subject :patient, "Pacjent"
      """)
    end
  end

  describe "D2: one translation per language, none into the term's own" do
    test "a second translation into one language is refused" do
      message =
        refused("TwoEnglish", """
          context :settlement, "Rozliczenia" do
            subdomain :supporting

            term "Wizyta" do
              definition "Spotkanie"
              translation :en, "Visit"
              translation :en, "Appointment"
            end
          end
        """)

      assert message =~
               ~s|D2: the term "Wizyta" in context :settlement has a second translation into :en (two_english.ex:10)|
    end

    test "a translation into the domain's language is refused" do
      message =
        refused("IntoPolish", """
          context :settlement, "Rozliczenia" do
            subdomain :supporting

            term "Wizyta" do
              definition "Spotkanie"
              translation :pl, "Wizyta"
            end
          end
        """)

      assert message =~
               ~s|is translated into :pl, which is the language it is written in (into_polish.ex:9)|
    end

    test "a context in another language takes that language as the term's own" do
      message =
        refused("IntoEnglish", """
          context :billing, "Billing" do
            subdomain :supporting
            language :en

            term "Visit" do
              definition "A patient's appointment"
              translation :en, "Visit"
            end
          end
        """)

      assert message =~ "is translated into :en, which is the language it is written in"
    end

    test "the control: one translation per other language compiles" do
      compiles("Translated", """
        context :settlement, "Rozliczenia" do
          subdomain :supporting

          term "Wizyta" do
            definition "Spotkanie"
            translation :en, "Visit"
            translation :de, "Besuch"
          end
        end
      """)
    end
  end

  describe "D3: a value is one type or fields, well formed, without cycles" do
    test "neither a type nor fields, and both, are refused" do
      message =
        refused("TypeOrFields", """
          value :nothing

          value :both, :string do
            field :street, :string
          end
        """)

      assert message =~
               "D3: value :nothing has neither a type nor fields; give it exactly one (type_or_fields.ex:4)"

      assert message =~
               "D3: value :both has both a type and fields; keep one (type_or_fields.ex:6)"
    end

    test "a unit on a type that does not count is refused" do
      assert refused("UnitOnText", "  value :note, :string, unit: :grosze\n") =~
               "D3: value :note has unit :grosze, and a unit counts only an :integer or a :decimal"
    end

    test "an unknown type, a malformed enum and a repeated member are refused" do
      message =
        refused("BadTypes", """
          value :price, :money
          value :method, {:enum, []}
          value :status, {:enum, [:open, :closed, :open]}
          value :flag, {:enum, [true]}

          value :line do
            field :amount, :cents
          end
        """)

      assert message =~ "value :price: type :money is neither a built-in type"
      assert message =~ "value :method: an enum is a non-empty list of members"
      assert message =~ "value :status: an enum repeats a member: [:open, :closed, :open]"
      assert message =~ "value :flag: an enum member is an atom, or an atom with a label"
      assert message =~ "value :line, field :amount: type :cents is neither a built-in type"
    end

    test "a value naming a context the domain does not declare is refused" do
      assert refused("NoSuchContext", "  value :money, :integer, context: :billing\n") =~
               "D3: value :money names context :billing, which this domain does not declare"
    end

    test "values referring to each other in a cycle are refused, once per cycle" do
      message =
        refused("Cycle", """
          value :a do
            field :b, :b
          end

          value :b do
            field :items, {:list, :a}
          end

          value :self do
            field :parent, :self
          end
        """)

      assert message =~ "D3: values refer to each other in a cycle: :a -> :b -> :a (cycle.ex:4)"
      assert message =~ "cycle: :self -> :self (cycle.ex:12)"
      refute message =~ ":b -> :a -> :b"
    end

    test "the control: every built-in type, a unit, labels, lists and nested values compile" do
      compiles("WellFormed", """
        context :settlement, "Rozliczenia", subdomain: :supporting
        value :money, :integer, unit: :grosze, label: "Kwota", context: :settlement
        value :rate, :decimal, unit: :percent
        value :method, {:enum, [card: "Karta", cash: "Gotówka"]}
        value :status, {:enum, [:open, :closed]}

        value :line do
          field :id, :id
          field :note, :string, optional: true
          field :amount, :money
          field :paid, :boolean
          field :on, :date
          field :at, :timestamp
          field :methods, {:list, :method}
        end

        value :invoice do
          field :lines, {:list, :line}
        end
      """)
    end
  end

  describe "the Spark schema (layer L1)" do
    test "an unknown option is refused with the file and line of the declaration" do
      error =
        domain(
          "UnknownOption",
          ~s|  context :settlement, "Rozliczenia", subdomain: :supporting, colour: :blue|
        )
        |> compile_error("unknown_option_domain.ex")

      assert Exception.message(error) =~ "unknown options [:colour]"
      assert Exception.message(error) =~ "unknown_option_domain.ex:4"
    end

    test "a missing use option is refused" do
      assert_raise Spark.Options.ValidationError, ~r/language/, fn ->
        Code.compile_string("""
        defmodule EhOsContract.DomainRulesTest.NoLanguage do
          use EhOsContract.Domain, name: :clinic
        end
        """)
      end
    end
  end
end
