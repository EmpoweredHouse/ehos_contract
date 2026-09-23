defmodule EhOsContract.DocsTest do
  @moduledoc """
  `docs/contract.md` describes the DSL, so it is **a second source of truth about
  the same thing** — which is exactly the failure this product detects in others.
  In one day we found four such divergences between the record and the code,
  including a DSL example in notes §1 using types that are not in the vocabulary.

  These tests are the mechanism that lets that file exist. Three things:

  1. **The example from the documentation compiles.** It is not an illustration,
     it is a fixture. The same rule the contract applies to rules, applied to its
     own documentation.
  2. **Every DSL key is described in the document.** Adding a key without
     describing it breaks a test.
  3. **Every gate in the "what refuses to compile" table has a test.** The table
     promises a compile error; the test proves the promise is true.

  The generated reference block guards itself — `mix eh_os_contract.docs --check` in
  `mix check` breaks the build if it is out of date.
  """

  use ExUnit.Case, async: true

  @path "docs/contract.md"
  # The gates themselves moved into the package on 2026-08-21 with the rest of the
  # engine's suite; this document did not, because `CLAUDE.md`, `README.md` and two
  # skills point at it by that path and `mix eh_os_contract.docs` resolves it from the working
  # directory. So the reference and the tests that prove it now live on opposite
  # sides of the seam, and this file reads across it by path. That is a debt with a
  # name, recorded in `PLAN.md`: the DSL reference is a package artifact still kept
  # as a host one.
  @gates "packages/eh_os_contract/test/compile_gates_test.exs"

  setup_all do
    {:ok, doc: File.read!(@path)}
  end

  describe "the example is a fixture, not an illustration" do
    test "every contract code block in the documentation compiles", %{doc: doc} do
      contracts = contract_blocks(doc)

      assert contracts != [],
             "documentation with no compilable example at all is checked by nothing"

      for {code, index} <- Enum.with_index(contracts) do
        # If this raises, the documentation lied about what compiles.
        assert [_ | _] = Code.compile_string(code),
               "block ##{index} from #{@path} does not compile"
      end
    end
  end

  describe "the vocabulary and the document cannot drift apart" do
    test "every key from `EhOsContract.Contract.schema/0` is named in the document", %{doc: doc} do
      missing =
        for {declaration, keys} <- EhOsContract.Contract.vocabulary(),
            key <- keys,
            not String.contains?(doc, "`#{key}`"),
            do: {declaration, key}

      assert missing == [],
             "DSL keys undescribed in #{@path}: #{inspect(missing)}. " <>
               "Adding a word to the DSL without describing it leaves a document that lies by omission."
    end

    test "every declaration has a section in the reference", %{doc: doc} do
      for declaration <- Map.keys(EhOsContract.Contract.vocabulary()) do
        assert String.contains?(doc, "### `#{declaration}`"),
               "no reference section for `#{declaration}`"
      end
    end
  end

  describe "the gate table promises a compile error" do
    test "the table has no more rows than there are gate tests", %{doc: doc} do
      # A weaker condition than a one-to-one mapping, but checkable, and it catches
      # the case that actually threatens: adding a promise to the table that nobody
      # has proven.
      promises = gate_table_rows(doc)
      tests = gate_tests()

      assert promises > 0

      assert promises <= tests,
             "the \"what refuses to compile\" table promises #{promises} gates, and there are " <>
               "#{tests} gate tests. A promise with no test is a sentence in prose."
    end
  end

  defp contract_blocks(doc) do
    ~r/```elixir\n(.*?)```/s
    |> Regex.scan(doc, capture: :all_but_first)
    |> Enum.map(&List.first/1)
    |> Enum.filter(&String.contains?(&1, "use EhOsContract.Contract"))
  end

  defp gate_table_rows(doc) do
    doc
    |> String.split("## What refuses to compile", parts: 2)
    |> List.last()
    |> String.split("\n## ", parts: 2)
    |> List.first()
    |> String.split("\n")
    |> Enum.count(&String.match?(&1, ~r/^\| .* \| .* \|$/))
    # minus the header and the separator
    |> Kernel.-(2)
  end

  defp gate_tests do
    @gates
    |> File.read!()
    |> then(&Regex.scan(~r/^\s+test "/m, &1))
    |> length()
  end
end
