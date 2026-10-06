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

  defp stored!(type) do
    {:ok, {:ok, [_row]}} =
      Repo.transaction(fn ->
        EhOsContract.Store.append(
          Repo,
          [
            %{
              type: type,
              contract: "DispatchRig.Ledger",
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

    log = capture_log(fn -> UndeclaredTypes.warn(Repo, [@ledger]) end)

    assert log =~ "retired.deposited, retired.withdrawn"

    assert log =~ "reset the engine's schema"

    assert log =~ "when none of them is worth keeping"
  end

  test "a long list is cut short, and says how many more" do
    for n <- 1..23, do: stored!("retired.kind_#{String.pad_leading("#{n}", 2, "0")}")

    log = capture_log(fn -> UndeclaredTypes.warn(Repo, [@ledger]) end)

    assert log =~ "retired.kind_20 and "
    refute log =~ "retired.kind_21"
  end

  test "a log it cannot read is reported, and the start goes on" do
    log = capture_log(fn -> assert UndeclaredTypes.warn(NoSuchRepo, [@ledger]) == [] end)

    assert log =~ "could not check the event log for undeclared types, and goes on"
  end

  test "control: a log of declared types only says nothing" do
    stored!(@declared)
    stored!(EhOsContract.ProcessManager.elapsed())

    assert capture_log(fn -> assert UndeclaredTypes.warn(Repo, [@ledger]) == [] end) == ""
  end
end
