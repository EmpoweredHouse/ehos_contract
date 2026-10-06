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

    assert UndeclaredTypes.undeclared(Repo, [@declared]) == [
             "retired.deposited",
             "retired.withdrawn"
           ]

    log = capture_log(fn -> UndeclaredTypes.warn(Repo, [@ledger]) end)

    assert log =~
             "the event log holds 2 type(s) no contract of this application declares: " <>
               "retired.deposited, retired.withdrawn"

    assert log =~ "reset the engine's schema"
  end

  test "control: a log of declared types only says nothing" do
    stored!(@declared)
    stored!(EhOsContract.ProcessManager.elapsed())

    assert capture_log(fn -> assert UndeclaredTypes.warn(Repo, [@ledger]) == [] end) == ""
  end
end
