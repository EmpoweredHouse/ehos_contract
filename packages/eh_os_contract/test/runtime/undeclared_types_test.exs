defmodule EhOsContract.UndeclaredTypesTest do
  @moduledoc """
  Plan DD, #175: the start-up warning about event types in the log that no contract
  declares — a log written before event types became `"<contract id>.<event>"`, which
  the rest of the engine would skip silently. One stored row of an undeclared type is
  named; declared types and the engine's own are not; with none, nothing is logged.
  """

  use EhOsContract.DataCase, async: false

  import ExUnit.CaptureLog

  alias EhOsContract.{Model, UndeclaredTypes}

  @ledger Model.fetch(DispatchRig.Ledger)
  @declared hd(@ledger.events).type

  defp stored!(type, contract \\ "dispatch_rig.ledger") do
    {:ok, {:ok, [_row]}} =
      Repo.transaction(fn ->
        EhOsContract.Store.append(
          Repo,
          [
            %{
              type: type,
              contract: contract,
              contract_version: "old",
              correlation_id: Ecto.UUID.generate(),
              actor: "system:old",
              occurred_at: EhOsContract.Clock.now(),
              payload: %{}
            }
          ],
          {:stream, "undeclared:#{System.unique_integer([:positive])}", 0}
        )
      end)
  end

  test "a type no contract declares is named, once, beside declared and engine types" do
    stored!(@declared)
    stored!(EhOsContract.Personal.erased_type())
    stored!("retired.deposited")
    stored!("retired.deposited")
    stored!("retired.withdrawn")

    # Contained, not equal: the test database is shared, and may hold rows of its own.
    undeclared = UndeclaredTypes.undeclared(Repo, [@declared])

    assert Enum.filter(undeclared, &String.starts_with?(&1, "retired.")) ==
             ["retired.deposited", "retired.withdrawn"]

    refute @declared in undeclared
    refute EhOsContract.Personal.erased_type() in undeclared

    # warn/2 reads the same log and returns what it found, among the rest; what it says
    # is report/1's, tested on lists below, as the warning names only the first twenty.
    capture_log(fn ->
      found = UndeclaredTypes.warn(Repo, [@ledger])
      assert "retired.deposited" in found and "retired.withdrawn" in found
    end)
  end

  # The warning's text is tested on lists, not on the shared log: other tests' rows,
  # or rows a `mix run` left there, would otherwise decide what it says.
  test "the warning says what the events are, and what a reset costs" do
    log = capture_log(fn -> UndeclaredTypes.report(["retired.deposited"]) end)

    assert log =~ "holds 1 type(s) no contract of this application declares: retired.deposited."
    assert log =~ "reset the engine's schema"
    assert log =~ "when none of them is worth keeping"
  end

  test "a long list is cut short, and says how many more" do
    types = for n <- 1..23, do: "retired.kind_#{String.pad_leading("#{n}", 2, "0")}"

    log = capture_log(fn -> UndeclaredTypes.report(types) end)

    assert log =~ "retired.kind_20 and 3 more"
    refute log =~ "retired.kind_21"
  end

  test "a log it cannot read is reported, and the start goes on" do
    log = capture_log(fn -> assert UndeclaredTypes.warn(NoSuchRepo, [@ledger]) == [] end)

    assert log =~ "could not check the event log for undeclared types, and goes on"
  end

  test "control: declared and engine types are not undeclared, and none says nothing" do
    stored!(@declared)
    stored!(EhOsContract.ProcessManager.elapsed())

    undeclared = UndeclaredTypes.undeclared(Repo, [@declared])
    refute @declared in undeclared
    refute EhOsContract.ProcessManager.elapsed() in undeclared

    assert capture_log(fn -> assert UndeclaredTypes.report([]) == [] end) == ""
  end

  describe "contract names (#179)" do
    test "a name no contract has as its id is named, once, beside known ones" do
      stored!(@declared)
      stored!(EhOsContract.Personal.erased_type(), "eh_os_contract")
      stored!(@declared, "DispatchRig.Ledger")
      stored!(@declared, "DispatchRig.Ledger")

      unknown = UndeclaredTypes.unknown_contracts(Repo, [@ledger.id])

      assert "DispatchRig.Ledger" in unknown
      assert Enum.count(unknown, &(&1 == "DispatchRig.Ledger")) == 1
      refute @ledger.id in unknown
      refute "eh_os_contract" in unknown

      capture_log(fn ->
        assert "DispatchRig.Ledger" in UndeclaredTypes.warn_contracts(Repo, [@ledger])
      end)
    end

    test "an id is matched whole: a longer one sharing its start is unknown" do
      stored!(@declared, "dispatch_rig.ledger.old")

      unknown = UndeclaredTypes.unknown_contracts(Repo, [@ledger.id])
      assert "dispatch_rig.ledger.old" in unknown
    end

    test "the warning says what the rows are, and what a reset costs" do
      log = capture_log(fn -> UndeclaredTypes.report_contracts(["DispatchRig.Ledger"]) end)

      assert log =~
               "files events under 1 contract name(s) no contract of this application has " <>
                 "as its id: DispatchRig.Ledger."

      assert log =~ "written before rows named a contract by its id"
      assert log =~ "when none of them is worth keeping"
      assert capture_log(fn -> assert UndeclaredTypes.report_contracts([]) == [] end) == ""
    end

    test "a log it cannot read is reported, and the start goes on" do
      log =
        capture_log(fn -> assert UndeclaredTypes.warn_contracts(NoSuchRepo, [@ledger]) == [] end)

      assert log =~ "could not check the event log for unknown contract names, and goes on"
    end
  end
end
