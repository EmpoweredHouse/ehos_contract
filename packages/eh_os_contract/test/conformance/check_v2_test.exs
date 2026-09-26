defmodule EhOsContract.CheckV2Test do
  @moduledoc """
  What `mix eh_os_contract.check` says about v2 contracts (plan E7c-2): the sentences
  v1 contracts get, where a v2 contract may legally say the thing, and whether it is
  implemented.
  """

  use ExUnit.Case, async: false

  alias EhOsContract.Check

  defp findings(contract), do: Check.v2_findings([contract])

  test "a process with no addressee, and a deadline its owner has not confirmed" do
    assert {:warn, "process :handling names no `accountable` role" <> _} =
             List.keyfind(findings(ProcessShapes.Next.Promised), :warn, 0)

    assert Enum.any?(
             findings(ProcessShapes.Next.Promised),
             &match?(
               {:warn, "process :handling: `deadline` = {3, :day} is not confirmed" <> _},
               &1
             )
           )
  end

  test "a deadline no run can be seen to end" do
    assert {:info, "process :branch declares `deadline` = {1, :day} and no event of it is" <> _} =
             List.keyfind(findings(DispatchRig.Branch), :info, 0)
  end

  test "control: a confirmed, addressed, implemented process has nothing to say" do
    assert findings(ProcessShapes.Next.Timed) == []
  end

  test "a contract with no implementation is legal, and noted" do
    Code.compile_string("""
    defmodule EhOsContract.CheckV2Test.Unimplemented do
      use EhOsContract.Next.Contract, domain: ProcessShapes.Domain, context: :batching

      aggregate :pile, "Pile" do
        identity :pile_id
        command :stack, "Stack", by: :batch_operator, emits: :stacked
        event :stacked, "Stacked"
      end

      process :piling, "Piling" do
        correlate :pile_id
        accountable :batch_operator

        promise :stays_stacked do
          from :stacked
          eventually :stacked
        end
      end
    end
    """)

    module = EhOsContract.CheckV2Test.Unimplemented

    assert [
             {:info, "promise :stays_stacked has no `within`, so it has no failing case" <> _},
             {:info,
              "EhOsContract.CheckV2Test.Unimplemented has no implementation, which a contract may (D3)" <>
                _}
           ] = findings(module)
  end
end
