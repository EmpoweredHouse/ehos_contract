defmodule EhOsContract.KeyBudgetTest do
  @moduledoc """
  A key over `EhOsContract.Key.budget/0` bytes, counted after escaping and with the
  name in front of it (issue #98): a stream's and a run's refuse the command with
  `:key_too_long`, 422 over HTTP, and write nothing; a process manager's stops its
  subscription at the event with `EhOsContract.Key.TooLongError`, where Postgres
  refused the entry before. Each at exactly the budget, which fits, and a byte over.

  The values are `|`, which escapes to three bytes, so three fields of 255 bytes come
  to 2297, past the budget: the reason a key is counted after escaping.

  Since plan DD, P2g (#228) the runs are process modules', filed under their ids:
  `KeyRig.Restocking`'s keyed by the bin, `KeyRig.AuditTrail`'s by its lot. An id is
  longer than the contract process's name it replaced, and it is in a run's entry
  twice, so the values that bring each run to exactly the budget are shorter.
  """

  use EhOsContract.DataCase, async: false

  # A failing subscription logs an error, which is the point of one of these tests.
  @moduletag :capture_log

  import Plug.Conn
  import Plug.Test

  alias EhOsContract.{
    Actor,
    CommandRecord,
    Event,
    Key,
    ProcessManager,
    ProcessManagerRecord,
    Subscription,
    SubscriptionRecord,
    Testing
  }

  alias KeyRig.Bins.Commands.StockBin
  alias KeyRig.Shelves.Commands.StockShelf

  @stocker Actor.credential("u-1", [
             "key_rig.stock_bin",
             "key_rig.count_bin",
             "key_rig.stock_shelf"
           ])
  @watch "key_rig.bins:process_manager:watch"

  # A value whose escaped form is `bytes` long.
  defp id(bytes), do: String.duplicate("|", div(bytes, 3)) <> String.duplicate("x", rem(bytes, 3))

  # Two fields of 255 bytes, each 765 escaped, so the third decides the length.
  @site String.duplicate("|", 255)
  @aisle String.duplicate("|", 255)

  defp shelf(shelf_id),
    do: %StockShelf{site_id: @site, aisle_id: @aisle, shelf_id: shelf_id}

  defp bin(bin_id, lot_id \\ "l-1"),
    do: %StockBin{site_id: @site, aisle_id: @aisle, bin_id: bin_id, lot_id: lot_id}

  defp written, do: {Repo.aggregate(Event, :count), Repo.aggregate(CommandRecord, :count)}

  describe "a stream's key" do
    test "of exactly the budget is accepted" do
      assert byte_size(Key.stream(:shelf, [@site, @aisle, id(510)])) == Key.budget()
      assert {:ok, _} = EhOsContract.dispatch(KeyRig.Shelves, shelf(id(510)), actor: @stocker)
    end

    test "a byte over is :key_too_long, and nothing is written" do
      assert byte_size(Key.stream(:shelf, [@site, @aisle, id(511)])) == Key.budget() + 1

      assert EhOsContract.dispatch(KeyRig.Shelves, shelf(id(511)), actor: @stocker) ==
               {:error, :key_too_long}

      assert written() == {0, 0}
    end

    test "over HTTP is a 422 naming the reason, not a 500" do
      opts = EhOsContract.Plug.init(contracts: [KeyRig.Shelves])

      conn =
        conn(
          :post,
          "/commands/key_rig.stock_shelf",
          Jason.encode!(%{site_id: @site, aisle_id: @aisle, shelf_id: id(511)})
        )
        |> put_req_header("content-type", "application/json")
        |> assign(:eh_os_contract_actor, @stocker)
        |> EhOsContract.Plug.call(opts)

      assert {conn.status, Jason.decode!(conn.resp_body)} ==
               {422, %{"error" => "key_too_long"}}

      assert written() == {0, 0}
    end
  end

  describe "a run's key" do
    # The module's id twice, as the process column and the instance id's prefix.
    @restocking "key_rig.restocking"
    defp bin_run(bin_id), do: [@restocking, Key.join([@restocking, @site, @aisle, bin_id])]

    test "of the bin's run, of exactly the budget, is accepted" do
      assert bin_run(id(479)) |> Enum.map(&byte_size/1) |> Enum.sum() == Key.budget()
      assert {:ok, _} = EhOsContract.dispatch(KeyRig.Bins, bin(id(479)), actor: @stocker)
    end

    test "of the bin's run, a byte over, is :key_too_long while the stream fits" do
      assert bin_run(id(480)) |> Enum.map(&byte_size/1) |> Enum.sum() == Key.budget() + 1
      assert Key.fits?([Key.stream(:bin, [@site, @aisle, id(480)])])

      assert EhOsContract.dispatch(KeyRig.Bins, bin(id(480)), actor: @stocker) ==
               {:error, :key_too_long}

      assert written() == {0, 0}
    end

    # `KeyRig.AuditTrail` includes the event in a run correlated by its lot, not its bin.
    @audit "key_rig.audit_trail"
    defp audit(lot_id), do: [@audit, Key.join([@audit, @site, @aisle, lot_id])]

    test "of a run keyed by another field, of exactly the budget, is accepted" do
      assert audit(id(477)) |> Enum.map(&byte_size/1) |> Enum.sum() == Key.budget()
      assert {:ok, _} = EhOsContract.dispatch(KeyRig.Bins, bin("x", id(477)), actor: @stocker)
    end

    test "of a run keyed by another field, a byte over, is :key_too_long while the bin's fits" do
      assert audit(id(478)) |> Enum.map(&byte_size/1) |> Enum.sum() == Key.budget() + 1
      assert Key.fits?(bin_run("x"))

      assert EhOsContract.dispatch(KeyRig.Bins, bin("x", id(478)), actor: @stocker) ==
               {:error, :key_too_long}

      assert written() == {0, 0}
    end
  end

  describe "a process manager's key" do
    # The run's timer stream, the longest key the run writes.
    defp watch(bin_id), do: ProcessManager.stream(@watch, Key.join([@site, @aisle, bin_id]))

    test "of exactly the budget starts its run" do
      assert byte_size(watch(id(477))) == Key.budget()
      {:ok, _} = EhOsContract.dispatch(KeyRig.Bins, bin(id(477)), actor: @stocker)

      assert %{failing: []} = Testing.drain(only: @watch)
      assert Repo.aggregate(ProcessManagerRecord, :count) == 1
    end

    test "a byte over stops its subscription with Key.TooLongError until it is skipped" do
      assert byte_size(watch(id(478))) == Key.budget() + 1
      # The dispatch's own keys fit: only the manager's does not. The bin's run is two
      # bytes short of the watch's, `KeyRig.Restocking`'s id chosen for it.
      assert Key.fits?(bin_run(id(478)))
      {:ok, _} = EhOsContract.dispatch(KeyRig.Bins, bin(id(478)), actor: @stocker)

      assert %{failing: [@watch]} = Testing.drain(only: @watch)

      assert %SubscriptionRecord{status: "failing", failure: "EhOsContract.Key.TooLongError"} =
               Repo.get!(SubscriptionRecord, @watch)

      assert Repo.aggregate(ProcessManagerRecord, :count) == 0

      assert :ok = Subscription.skip(Repo, @watch)
      assert %{failing: []} = Testing.drain(only: @watch)
      assert Repo.aggregate(ProcessManagerRecord, :count) == 0
    end

    test "over the budget on an event no run takes is taken as before, not a stop" do
      # The watch reacts on a count, but only a restock starts a run: nothing to write.
      count = %KeyRig.Bins.Commands.CountBin{site_id: @site, aisle_id: @aisle, bin_id: id(478)}
      {:ok, _} = EhOsContract.dispatch(KeyRig.Bins, count, actor: @stocker)

      assert %{failing: []} = Testing.drain(only: @watch)
      assert Repo.aggregate(ProcessManagerRecord, :count) == 0
    end

    test "names the manager and the bytes, and no value" do
      {:ok, _} = EhOsContract.dispatch(KeyRig.Bins, bin(id(478)), actor: @stocker)
      [row] = Repo.all(Event)
      consumer = Enum.find(EhOsContract.Implementations.subscribed(), &(&1.key == @watch))

      error =
        assert_raise Key.TooLongError, fn ->
          ProcessManager.handle!(Repo, consumer, row, [], false)
        end

      assert error.message =~ @watch
      assert error.message =~ "2049 bytes, over the budget of 2048"
      refute error.message =~ "|"
    end
  end
end
