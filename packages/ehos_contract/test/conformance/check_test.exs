defmodule EhosContract.CheckTest do
  @moduledoc """
  What `mix ehos_contract.check` says about v2 contracts (plan E7c-2): the sentences
  v1 contracts get, where a v2 contract may legally say the thing, and whether it is
  implemented.
  """

  use ExUnit.Case, async: false

  alias EhosContract.Check

  defp findings(contract),
    do: for(f <- Check.findings([contract]), do: {f.level, f.rule, f.message})

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
      refute Check.no_contracts?(EhosContract.Registry.contracts())
    end
  end

  # Plan DD, P2g (#228): the process shapes' processes are modules, which the check reads
  # through `process_module_findings/1`, named by their ids.
  defp process_findings(module),
    do: for(f <- Check.process_module_findings([module]), do: {f.level, f.rule, f.message})

  # Plan DD, L4 (#326): the owner's view names a stage by its label. Control:
  # `ProcessShapes.Timing`, whose stages have labels, below.
  test "a stage without a label is noted, one finding a stage" do
    assert [
             "stage :intake of process \"process_shapes.handling\" has no label" <> _,
             "stage :decision" <> _,
             "stage :closing" <> _
           ] =
             for(
               {:info, "owner-view-without-label", message} <-
                 process_findings(ProcessShapes.Handling),
               do: message
             )

    # At the stage, not at the module's `use`.
    assert [{"handling.ex", 20} | _] =
             for(
               %{rule: "owner-view-without-label"} = finding <-
                 Check.process_module_findings([ProcessShapes.Handling]),
               do: place(finding)
             )
  end

  defp place(finding) do
    {file, line} = EhosContract.Check.Finding.place(finding)
    {Path.basename(file), line}
  end

  test "a process with no addressee, and a deadline its owner has not confirmed" do
    assert {:warn, "process-without-accountable",
            ~s(process "process_shapes.handling" names no `accountable` role) <> _} =
             List.keyfind(process_findings(ProcessShapes.Handling), :warn, 0)

    assert Enum.any?(
             process_findings(ProcessShapes.Handling),
             &match?(
               {:warn, "unverified-declaration",
                ~s(process "process_shapes.handling": `deadline` = {3, :day} is not confirmed) <>
                  _},
               &1
             )
           )
  end

  test "control: a confirmed, addressed, implemented process has nothing to say" do
    assert findings(ProcessShapes.Timed) == []
    assert process_findings(ProcessShapes.Timing) == []
  end

  test "a contract implemented in part names what dispatch will refuse, its query too" do
    assert [{:warn, "declaration-without-implementation", message}] =
             findings(DispatchRig.Unfinished)
             |> Enum.filter(&(elem(&1, 0) == :warn and elem(&1, 2) =~ "implements"))

    assert message =~ "read_model notes"
    assert message =~ "query notes_of"
  end

  # Plan DD, V2 (#338): reading an older row of a unit that records only can still call its
  # code, so such a unit is one dispatch looks an implementation up for.
  test "a unit that records only, with a step by a function, is looked up; control: implemented" do
    Code.compile_string("""
    defmodule EhosContract.CheckTest.Upcasting do
      use EhosContract.Contract, domain: ProcessShapes.Domain, context: :batching, id: "process_shapes.upcasting"

      aggregate :tally, "Tally" do
        identity :tally_id

        event :counted, "Counted", recorded_by: :batch_operator, schema_version: 2 do
          upcast from: 1, function: :from_one
        end
      end
    end
    """)

    assert [{:info, "contract-without-implementation", _}] =
             findings(EhosContract.CheckTest.Upcasting)
             |> Enum.filter(&(elem(&1, 1) =~ "implementation"))

    # `UpcastRig.Fees` implements the fee, whose event has a step by a function.
    assert [] =
             findings(UpcastRig.Demands) |> Enum.filter(&(elem(&1, 1) =~ "implementation"))
  end

  test "a contract with no implementation is legal, and noted" do
    Code.compile_string("""
    defmodule EhosContract.CheckTest.Unimplemented do
      use EhosContract.Contract, domain: ProcessShapes.Domain, context: :batching, id: "process_shapes.unimplemented"

      aggregate :pile, "Pile" do
        identity :pile_id
        command :stack, "Stack", by: :batch_operator, emits: :stacked
        event :stacked, "Stacked"
      end
    end

    defmodule EhosContract.CheckTest.Piling do
      use EhosContract.Process,
        id: "process_shapes.piling",
        domain: ProcessShapes.Domain,
        label: "Piling",
        accountable: :batch_operator

      correlate :pile_id
      stage :piling, "Piling", include: [{EhosContract.CheckTest.Unimplemented, [:stacked]}]

      promise :stays_stacked do
        from :stacked
        eventually :stacked
      end
    end
    """)

    module = EhosContract.CheckTest.Unimplemented

    assert [
             {:info, "contract-without-implementation",
              "EhosContract.CheckTest.Unimplemented has no implementation, which a contract may" <>
                _}
           ] = findings(module)

    assert [
             {:info, "promise-without-within",
              "promise :stays_stacked has no `within`, so it has no failing case" <> _}
           ] = process_findings(EhosContract.CheckTest.Piling)
  end

  test "a contract made only of recorded events needs no implementation" do
    Code.compile_string("""
    defmodule EhosContract.CheckTest.RecordedOnly do
      use EhosContract.Contract, domain: ProcessShapes.Domain, context: :batching, id: "process_shapes.recorded_only"

      aggregate :inbox, "Inbox" do
        identity :message_id
        event :message_received, "Message received", recorded_by: :batch_operator
      end
    end
    """)

    assert findings(EhosContract.CheckTest.RecordedOnly) == []
  end
end
