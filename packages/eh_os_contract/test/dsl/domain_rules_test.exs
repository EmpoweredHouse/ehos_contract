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
