defmodule EhOsContract.CheckV2Test do
  @moduledoc """
  What `mix eh_os_contract.check` says about v2 contracts (plan E7c-2): the sentences
  v1 contracts get, where a v2 contract may legally say the thing, and whether it is
  implemented.
  """

  use ExUnit.Case, async: false

  alias EhOsContract.Check

  defp findings(contract),
    do: for(f <- Check.v2_findings([contract]), do: {f.level, f.rule, f.message})

  describe "nothing to check" do
    test "an empty registry is recognised as such" do
      # Without this, a scan pointed at the wrong application prints the same three
      # zeroes as a clean build. It is not a hypothetical: it is what this engine did
      # the first time it compiled as its own package, scanning itself.
      assert Check.no_contracts?([])
    end

    test "control: this package has something to check, in its v2 contracts alone" do
      # A predicate that answered "empty" for everything would satisfy the test above
      # and silence the whole task. The v2 contracts are named on their own, so this
      # still says something once v1's registry is gone.
      refute Check.no_contracts?()
      refute Check.no_contracts?(EhOsContract.Registry.v2_contracts())
    end
  end

  test "a process with no addressee, and a deadline its owner has not confirmed" do
    assert {:warn, "process-without-accountable",
            "process :handling names no `accountable` role" <> _} =
             List.keyfind(findings(ProcessShapes.Promised), :warn, 0)

    assert Enum.any?(
             findings(ProcessShapes.Promised),
             &match?(
               {:warn, "unverified-declaration",
                "process :handling: `deadline` = {3, :day} is not confirmed" <> _},
               &1
             )
           )
  end

  test "a deadline no run can be seen to end" do
    assert {:info, "deadline-without-terminal-event",
            "process :branch declares `deadline` = {1, :day} and no event of it is" <> _} =
             List.keyfind(findings(DispatchRig.Branch), :info, 0)
  end

  test "control: a confirmed, addressed, implemented process has nothing to say" do
    assert findings(ProcessShapes.Timed) == []
  end

  test "a contract implemented in part names what dispatch will refuse, its query too" do
    assert [{:warn, "declaration-without-implementation", message}] =
             findings(DispatchRig.Unfinished)
             |> Enum.filter(&(elem(&1, 0) == :warn and elem(&1, 2) =~ "implements"))

    assert message =~ "read_model notes"
    assert message =~ "query notes_of"
  end

  test "a contract with no implementation is legal, and noted" do
    Code.compile_string("""
    defmodule EhOsContract.CheckV2Test.Unimplemented do
      use EhOsContract.Contract, domain: ProcessShapes.Domain, context: :batching

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
             {:info, "promise-without-within",
              "promise :stays_stacked has no `within`, so it has no failing case" <> _},
             {:info, "contract-without-implementation",
              "EhOsContract.CheckV2Test.Unimplemented has no implementation, which a contract may (D3)" <>
                _}
           ] = findings(module)
  end

  test "a contract made only of recorded events needs no implementation" do
    Code.compile_string("""
    defmodule EhOsContract.CheckV2Test.RecordedOnly do
      use EhOsContract.Contract, domain: ProcessShapes.Domain, context: :batching

      aggregate :inbox, "Inbox" do
        identity :message_id
        event :message_received, "Message received", recorded_by: :batch_operator
      end

      process :intake, "Intake", accountable: :batch_operator do
        correlate :message_id
      end
    end
    """)

    assert findings(EhOsContract.CheckV2Test.RecordedOnly) == []
  end
end
