defmodule EhOsContract.LogMetadataTest do
  @moduledoc """
  What an application logs while the engine works carries that work's correlation identifier, one
  across every application it passes through, as the Logger's metadata `correlation_id` (#298): in
  a command's dispatch, in an effect, delivered in the transaction or as a job, and in a process
  manager's reaction. Once the work is done, what was there before is back, so a process that
  handles one event after another never writes one's identifier on the next one's lines.

  `DispatchRig`'s audit, branch notice and first-deposit chase each log a line at debug level.
  """

  use EhOsContract.DataCase, async: false

  import ExUnit.CaptureLog

  alias DispatchRig.Ledger
  alias DispatchRig.Ledger.Commands.{Deposit, OpenAccount, Withdraw}
  alias DispatchRig.Ledger.Events.InterestRecorded
  alias EhOsContract.{Actor, Clock, LogMetadata, Testing}

  @clerk Actor.credential("u-1", [
           "dispatch_rig.open_account",
           "dispatch_rig.deposit",
           "dispatch_rig.withdraw"
         ])

  @work "0f0e4a1c-6c2e-4d5b-9a7e-3b1d2c4e5f60"

  setup do
    {:ok, _} =
      EhOsContract.dispatch(Ledger, %OpenAccount{account_id: "a-1", branch_id: "b-7"},
        actor: @clerk
      )

    {:ok, _} =
      EhOsContract.dispatch(Ledger, %Deposit{account_id: "a-1", amount: 10}, actor: @clerk)

    # After the setup, so its queries are not printed.
    level = Logger.level()
    Logger.configure(level: :debug)
    on_exit(fn -> Logger.configure(level: level) end)
    :ok
  end

  @rig [
    "audited a withdrawal",
    "notified the branch",
    "chased interest before a deposit",
    "chased a first deposit, a day on"
  ]

  # The rig's lines logged by `fun`, each as `<correlation_id> |<message>`; Ecto's queries, also at
  # debug level, are left out.
  defp lines(fun) do
    [format: "$metadata|$message\n", metadata: [:correlation_id], level: :debug]
    |> capture_log(fun)
    |> String.split("\n", trim: true)
    |> Enum.map(&String.replace_prefix(&1, "correlation_id=", ""))
    |> Enum.map(&String.trim_leading/1)
    |> Enum.filter(fn line -> Enum.any?(@rig, &String.ends_with?(line, "|" <> &1)) end)
  end

  defp dispatch(command, opts \\ []),
    do: {:ok, _} = EhOsContract.dispatch(Ledger, command, [actor: @clerk] ++ opts)

  test "a line logged in a command's dispatch carries the command's correlation" do
    assert lines(fn ->
             dispatch(%Withdraw{account_id: "a-1", amount: 3}, correlation_id: @work)
           end) ==
             ["#{@work} |audited a withdrawal"]
  end

  test "a command dispatched with no correlation is given one, and its lines carry it" do
    assert [line] = lines(fn -> dispatch(%Withdraw{account_id: "a-1", amount: 3}) end)
    assert [id, "audited a withdrawal"] = String.split(line, " |")
    assert {:ok, _uuid} = Ecto.UUID.cast(id)
  end

  test "an effect run as a job logs with the correlation of the event it handles" do
    dispatch(%Deposit{account_id: "a-1", amount: 1000}, correlation_id: @work)

    assert lines(fn -> Oban.drain_queue(queue: :events) end) ==
             ["#{@work} |notified the branch"]
  end

  test "a process manager's reaction logs with the correlation of the event it takes" do
    # An account with no deposit yet, whose interest the chase reacts to.
    dispatch(%OpenAccount{account_id: "a-2", branch_id: "b-7"})
    Testing.drain()

    {:ok, _} =
      EhOsContract.record(Ledger, %InterestRecorded{account_id: "a-2", amount: 3},
        actor: Actor.system(:nightly_import),
        correlation_id: @work
      )

    assert "#{@work} |chased interest before a deposit" in lines(fn -> Testing.drain() end)
  end

  test "a process manager's timer logs with the correlation of the run that set it" do
    opened = ~U[2026-09-01 09:00:00Z]

    Clock.at(opened, fn ->
      dispatch(%OpenAccount{account_id: "a-3", branch_id: "b-7"}, correlation_id: @work)
      Testing.drain()
    end)

    lines = lines(fn -> Clock.at(DateTime.add(opened, 25, :hour), &Testing.drain/0) end)
    assert "#{@work} |chased a first deposit, a day on" in lines
  end

  test "an identifier that is not a UUID's text reaches no line, and stops nothing" do
    for id <- [
          "not-a-uuid",
          String.duplicate("a", 10_000),
          "#{@work}\nforged",
          # 36 bytes, the length of a UUID's text, and not one.
          String.duplicate("z", 36),
          "0f0e4a1c-6c2e-4d5b-9a7e-3b1d2c4e5f6\n",
          42
        ] do
      assert LogMetadata.correlated(id, fn -> Logger.metadata()[:correlation_id] end) == nil
    end
  end

  test "an identifier in upper case is written as the log keeps it, in lower case" do
    upper = String.upcase(@work)
    assert LogMetadata.correlated(upper, fn -> Logger.metadata()[:correlation_id] end) == @work
  end

  test "a correlation inside another's puts the outer one back" do
    inner = "1a2b3c4d-0000-4000-8000-000000000001"

    LogMetadata.correlated(@work, fn ->
      assert LogMetadata.correlated(inner, fn -> Logger.metadata()[:correlation_id] end) == inner
      assert Logger.metadata()[:correlation_id] == @work
    end)

    assert Logger.metadata()[:correlation_id] == nil
  end

  test "once the work is done, the correlation that was there before is back" do
    Logger.metadata(correlation_id: "the caller's own")
    dispatch(%Withdraw{account_id: "a-1", amount: 3}, correlation_id: @work)
    assert Logger.metadata()[:correlation_id] == "the caller's own"

    Logger.metadata(correlation_id: nil)
    dispatch(%Withdraw{account_id: "a-1", amount: 3}, correlation_id: @work)
    assert Logger.metadata()[:correlation_id] == nil
  end

  test "it is put back when the work raises, too" do
    assert_raise ArgumentError, fn ->
      LogMetadata.correlated(@work, fn -> raise ArgumentError, "boom" end)
    end

    assert Logger.metadata()[:correlation_id] == nil
  end
end
