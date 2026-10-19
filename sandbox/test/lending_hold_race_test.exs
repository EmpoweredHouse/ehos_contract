defmodule Lending.HoldRaceTest do
  @moduledoc """
  Holds on a copy, raced on real commits: **in a race over one copy the boundary's
  invariants never break, and its conflict check reads only a range of the primary
  key.**

  The boundary is `Lending.Contracts.Circulation`'s hold: one hold per copy, and none on
  a withdrawn copy. Everything here commits, on `EhOsContractHost.CommitRepo`, with the
  engine's `:repo` pointed at it for the test: the sandbox's own repo gives each test
  one connection, which serialises every dispatch.
  """

  use ExUnit.Case, async: false

  import Ecto.Query

  alias EhOsContract.{Actor, Event, Rejection, Store}
  alias EhOsContractHost.CommitRepo, as: Repo
  alias Lending.Contracts.Circulation
  alias Lending.Contracts.Circulation.Commands.{LendCopy, PlaceHold, WithdrawCopy}

  @librarian Actor.credential("librarian-una", ["lending.withdraw_copy"])

  setup do
    previous = Application.fetch_env!(:eh_os_contract, :repo)
    Application.put_env(:eh_os_contract, :repo, Repo)
    on_exit(fn -> Application.put_env(:eh_os_contract, :repo, previous) end)
    # The log keeps every copy across tests, so each test races over a copy of its own.
    %{copy: "copy-race-#{System.unique_integer([:positive])}"}
  end

  defp hold(copy, member) do
    EhOsContract.dispatch(
      Circulation,
      %PlaceHold{copy_id: copy, member_id: member},
      actor: Actor.credential(member, ["lending.place_hold"])
    )
  end

  defp lend(copy, member) do
    EhOsContract.dispatch(
      Circulation,
      %LendCopy{
        loan_id: "#{copy}-loan",
        copy_id: copy,
        member_id: member,
        card_id: "card-ada",
        due_at: ~U[2026-10-22 17:00:00Z]
      },
      actor: Actor.credential("librarian-una", ["lending.lend_copy"])
    )
  end

  defp withdraw(copy),
    do: EhOsContract.dispatch(Circulation, %WithdrawCopy{copy_id: copy}, actor: @librarian)

  # This copy's events in the log, in the order they were appended.
  defp log(copy) do
    Repo.all(
      from(e in Event,
        where: fragment("? @> ?::text[]", e.tags, ^["copy_id:#{copy}"]),
        order_by: e.position,
        select: e.type
      )
    )
  end

  test "a copy withdrawn while a hold waits to append: the hold is decided again, and refused",
       %{copy: copy} do
    parent = self()

    # Holds the append lock, so the hold reads its boundary, decides on a copy still in
    # circulation, and waits to append; the copy is withdrawn under the same lock.
    holder =
      Task.async(fn ->
        Repo.transaction(fn ->
          :ok = Store.lock(Repo)
          send(parent, :locked)

          receive do
            :withdraw -> {:ok, _} = withdraw(copy)
          end
        end)
      end)

    assert_receive :locked
    member = Task.async(fn -> hold(copy, "member-ada") end)
    wait_for_a_writer_blocked_on_the_lock()
    send(holder.pid, :withdraw)
    assert {:ok, {:ok, _}} = Task.await(holder)

    assert {:error, %Rejection{invariant: :withdrawn_copy_takes_no_hold}} = Task.await(member)
    assert log(copy) == ["lending.circulation.withdrawn_from_circulation"]
  end

  test "ten members ask for one copy at once: one hold between them", %{copy: copy} do
    answers =
      for n <- 1..10 do
        Task.async(fn -> until_settled(fn -> hold(copy, "member-#{n}") end, 20) end)
      end
      |> Enum.map(&Task.await(&1, 60_000))

    assert Enum.count(answers, &match?({:ok, _}, &1)) == 1

    assert Enum.count(
             answers,
             &match?({:error, %Rejection{invariant: :one_hold_per_copy}}, &1)
           ) == 9

    assert log(copy) == ["lending.circulation.hold_placed"]
  end

  # Dispatch retries a conflict three times; one whose three all met another writer is
  # sent again, as a host would, a bounded number of times.
  defp until_settled(_send, 0), do: flunk("a dispatch kept conflicting")

  defp until_settled(send, sends) do
    case send.() do
      {:error, :conflict} -> until_settled(send, sends - 1)
      settled -> settled
    end
  end

  test "the hold's conflict check reads the log after the head, by the primary key",
       %{copy: copy} do
    # Ada's hold ends when the copy is lent to her, so Bob's hold is decided over both.
    {:ok, _} = hold(copy, "member-ada")
    {:ok, _} = lend(copy, "member-ada")

    # The check is the statement the store runs under the lock, captured as it runs
    # and explained with its own parameters, on a table with statistics, as autovacuum
    # keeps a real one. Without them the planner guesses a third of the table for
    # `position > head`, and may serve a consulted type by the index of `type` alone,
    # reading that type's whole history. Sequential scans are switched off because the
    # table is small enough for the planner to prefer one whatever the indexes: what is
    # asserted is which index serves the check.
    parent = self()
    handler = "copy-hold-explain-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler,
      [:eh_os_contract_host, :commit_repo, :query],
      fn _event, _measurements, %{query: sql, params: params}, _ ->
        if sql =~ "SELECT TRUE" and sql =~ ~s("position" > $1),
          do: send(parent, {:check, sql, params})
      end,
      nil
    )

    try do
      assert {:ok, _} = hold(copy, "member-bob")
    after
      :telemetry.detach(handler)
    end

    assert_received {:check, sql, params}

    Repo.query!("ANALYZE eh_os_contract_events")

    {:ok, plan} =
      Repo.transaction(fn ->
        Repo.query!("SET LOCAL enable_seqscan = off")
        Repo.query!("EXPLAIN " <> sql, params).rows |> List.flatten() |> Enum.join("\n")
      end)

    refute plan =~ "Seq Scan", plan
    refute plan =~ "Bitmap", plan

    assert plan =~
             ~r/Index Scan using eh_os_contract_events_pkey .*\n\s+Index Cond: \("position" > /,
           plan
  end

  defp wait_for_a_writer_blocked_on_the_lock(tries \\ 200)

  defp wait_for_a_writer_blocked_on_the_lock(0),
    do: flunk("the hold never waited for the lock")

  defp wait_for_a_writer_blocked_on_the_lock(tries) do
    %{rows: [[waiting]]} =
      Repo.query!("""
      SELECT count(*) FROM pg_locks
      WHERE locktype = 'advisory' AND NOT granted
        AND database = (SELECT oid FROM pg_database WHERE datname = current_database())
      """)

    if waiting == 0 do
      Process.sleep(10)
      wait_for_a_writer_blocked_on_the_lock(tries - 1)
    end
  end
end
