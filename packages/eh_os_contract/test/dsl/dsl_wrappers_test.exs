defmodule EhOsContract.DslWrappersTest do
  @moduledoc """
  v2 §16, D13: **options stay beside a `do` block.** `EhOsContract.DslWrappers`
  gives every entity that takes a block one more arity, generated from the entity's
  definition. D13 holds on two conditions, and this file pins both on the domain DSL:

  1. a DSL error still points at the file and line of the declaration, not at the
     wrapper;
  2. the formatter keeps the four-argument form without parentheses.

  If either fails, D13's fallback is options inside the block, and the question goes
  back to the user. `sandbox/test/rehmed_domain_test.exs` pins the second in a
  consumer, through `import_deps`.
  """

  use EhOsContract.DslCase, async: false

  alias EhOsContract.{DslWrappers, Model}

  defp domain(name, body) do
    """
    defmodule EhOsContract.DslWrappersTest.#{name} do
      use EhOsContract.Domain, name: :clinic, language: :pl

    #{body}

      subdomain :supporting, "Supporting", type: :supporting
    end
    """
  end

  defp compiled(name, body) do
    compile(domain(name, body), "#{Macro.underscore(name)}.ex")
    Model.fetch(Module.concat(__MODULE__, name))
  end

  defp refused(name, body) do
    error = compile_error(domain(name, body), "#{Macro.underscore(name)}.ex")
    {Exception.message(error), error.location}
  end

  describe "a declaration with options beside its block" do
    test "compiles to the same model as the options written inside the block" do
      beside =
        compiled("Beside", """
          context :settlement, "Rozliczenia", subdomain: :supporting, source: "CTX-05" do
            term "Wizyta", definition: "Spotkanie pacjenta ze specjalistą" do
              translation :en, "Visit", definition: "A patient's appointment with a specialist"
              avoid "Seans"
            end
          end

          value :address, label: "Adres", context: :settlement do
            field :street, :string
          end
        """)

      inside =
        compiled("Inside", """
          context :settlement, "Rozliczenia" do
            subdomain :supporting
            source "CTX-05"

            term "Wizyta" do
              definition "Spotkanie pacjenta ze specjalistą"
              translation :en, "Visit", definition: "A patient's appointment with a specialist"
              avoid "Seans"
            end
          end

          value :address do
            label "Adres"
            context :settlement
            field :street, :string
          end
        """)

      assert beside.version == inside.version
      assert beside.digests == inside.digests
      assert [%{label: "Adres", type: nil, context: :settlement}] = beside.values
    end

    test "leaves the forms Spark already had as they were" do
      model =
        compiled("Unwrapped", """
          context :settlement, "Rozliczenia", subdomain: :supporting
          value :money, :integer, unit: :grosze, label: "Kwota"
          value :note, :string

          value :address do
            field :street, :string
          end
        """)

      assert [
               %{name: :money, type: :integer, unit: :grosze, label: "Kwota"},
               %{name: :note, type: :string, label: nil},
               %{name: :address, type: nil, fields: [%{name: :street}]}
             ] = model.values
    end
  end

  describe "condition 1: an error points at the declaration, not at the wrapper" do
    # One refusal per test. An entity that fails to build inside another's block
    # leaves Spark's nesting state in the process dictionary, and the next module
    # compiled in the same process would trip over it.
    test "an unknown option beside a context's block" do
      {context, context_at} =
        refused("UnknownContextOption", """
          context :settlement, "Rozliczenia", subdomian: :supporting do
            term "Wizyta", definition: "Spotkanie"
          end
        """)

      assert context =~ "defined in unknown_context_option.ex:4"
      assert context =~ "unknown options [:subdomian]"
      assert context_at[:file] == ~c"unknown_context_option.ex"
      assert context_at[:location] == 4
    end

    test "an unknown option beside a nested term's block" do
      {term, term_at} =
        refused("UnknownTermOption", """
          context :settlement, "Rozliczenia", subdomain: :supporting do
            term "Wizyta", defintion: "Spotkanie" do
              translation :en, "Visit", definition: "A patient's appointment with a specialist"
            end
          end
        """)

      assert term =~ "defined in unknown_term_option.ex:5"
      assert term =~ "unknown options [:defintion]"
      assert term_at[:location] == 5
    end

    # `value` goes another way: Spark takes the options for its optional `type`, and
    # the transform `DslWrappers` gives it checks them.
    test "an unknown option beside a value's block" do
      {value, value_at} =
        refused("UnknownValueOption", """
          value :address, lable: "Adres" do
            field :street, :string
          end
        """)

      assert value =~ "defined in unknown_value_option.ex:4"
      assert value =~ "unknown options [:lable]"
      assert value_at[:location] == 4
    end

    test "a domain rule broken inside and beside wrapped declarations names each line" do
      {message, at} =
        refused("RuleInWrapped", """
          context :settlement, "Rozliczenia", subdomain: :supporting
          context :settlement, "Rozliczenia", subdomain: :supporting do
            term "Wizyta", definition: "Spotkanie"
            term "Wizyta", definition: "Spotkanie" do
              translation :pl, "Wizyta", definition: "Umówione spotkanie pacjenta ze specjalistą"
            end
          end
        """)

      assert message =~ "D1: two contexts are named :settlement (rule_in_wrapped.ex:5)"
      assert message =~ ~s|defines the term "Wizyta" twice (rule_in_wrapped.ex:7)|

      assert message =~
               "is translated into :pl, which is the language it is written in (rule_in_wrapped.ex:8)"

      assert at[:file] == ~c"rule_in_wrapped.ex"
      assert at[:location] == 5
    end

    test "options that are not a literal keyword list are refused at the call" do
      error =
        assert_raise CompileError, fn ->
          compile(
            domain("NotLiteral", """
              @options [subdomain: :supporting]
              context :settlement, "Rozliczenia", @options do
                term "Wizyta", definition: "Spotkanie"
              end
            """),
            "not_literal.ex"
          )
        end

      assert error.file =~ "not_literal.ex"
      assert error.line == 5
      assert error.description =~ "must be a literal keyword list"
    end
  end

  describe "an entity's own transform" do
    defp leaf(transform) do
      %Spark.Dsl.Entity{
        name: :note,
        target: EhOsContract.Domain.Dsl.Avoid,
        args: [:text],
        schema: [text: [type: :string, required: true]],
        transform: transform
      }
    end

    defp parent(child, args) do
      %Spark.Dsl.Entity{
        name: :box,
        target: EhOsContract.Domain.Dsl.Term,
        args: args,
        entities: [avoid: [child]],
        schema: [text: [type: :string], definition: [type: :string]]
      }
    end

    defp section(entity),
      do: %Spark.Dsl.Section{name: :probe, top_level?: true, entities: [entity]}

    test "is left alone where no transform of the wrappers' is needed" do
      transform = {__MODULE__, :noop, []}

      attached =
        DslWrappers.attach(section(parent(leaf(transform), [:text])), __MODULE__.LeftAlone)

      [%{entities: [avoid: [child]]}] = attached.entities
      assert child.transform == transform
    end

    test "is refused where the wrappers would need one of their own" do
      box = %{parent(leaf(nil), [{:optional, :text}]) | transform: {__MODULE__, :noop, []}}

      error =
        assert_raise ArgumentError, fn -> DslWrappers.attach(section(box), __MODULE__.Refused) end

      assert error.message =~
               "box takes a block and an optional argument, and has its own transform"
    end
  end

  describe "condition 2: the formatter keeps the four-argument form" do
    # D13 expected to need the wrappers' arities exported beside Spark's. It does not:
    # the formatter never adds parentheses to a call that has a `do` block, whatever
    # `locals_without_parens` says. What the export still decides is the calls
    # without a block, inside and outside it, and those are Spark's own arities.
    @source """
    context :settlement, "Rozliczenia", subdomain: :supporting do
      term "Wizyta", definition: "Spotkanie" do
        translation :en, "Visit", definition: "A patient's appointment with a specialist"
      end
    end

    value :address, label: "Adres" do
      field :street, :string
    end
    """

    test "without parentheses, under the package's export" do
      {formatter, _} = Code.eval_file(".formatter.exs")
      assert format(@source, formatter[:export][:locals_without_parens]) == @source
    end

    test "control: with nothing exported, only the calls without a block gain parentheses" do
      rewritten = format(@source, [])

      assert rewritten =~ ~s|context :settlement, "Rozliczenia", subdomain: :supporting do|
      assert rewritten =~ ~s|term "Wizyta", definition: "Spotkanie" do|
      assert rewritten =~ ~s|value :address, label: "Adres" do|

      assert rewritten =~
               ~s|translation(:en, "Visit", definition: "A patient's appointment with a specialist")|

      assert rewritten =~ ~s|field(:street, :string)|
    end
  end

  defp format(source, locals) do
    IO.iodata_to_binary([Code.format_string!(source, locals_without_parens: locals), "\n"])
  end
end
