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
