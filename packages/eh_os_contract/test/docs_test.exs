defmodule EhOsContract.DocsTest do
  @moduledoc """
  `docs/contract.md` describes the DSL, so it is **a second source of truth about
  the same thing** — which is exactly the failure this product detects in others.
  In one day we found four such divergences between the record and the code,
  including a DSL example in notes §1 using types that are not in the vocabulary.

  These tests are the mechanism that lets that file exist. Two things:

  1. **The example from the documentation compiles.** It is not an illustration,
     it is a fixture. The same rule the contract applies to rules, applied to its
     own documentation.
  2. **Every DSL key is described in the document.** Adding a key without
     describing it breaks a test.

  A third test counted the rows of the "what refuses to compile" table against the
  tests of `compile_gates_test.exs`. Those tests pinned v1's gates and went with v1's
  tests (v2 plan, E11a); the document and this file go with v1's library.

  The generated reference block guards itself — `mix eh_os_contract.docs --check` in
  this package's `mix check` breaks the build if it is out of date.
  """

  use ExUnit.Case, async: true

  @path "docs/contract.md"

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

  defp contract_blocks(doc) do
    ~r/```elixir\n(.*?)```/s
    |> Regex.scan(doc, capture: :all_but_first)
    |> Enum.map(&List.first/1)
    |> Enum.filter(&String.contains?(&1, "use EhOsContract.Contract"))
  end
end
