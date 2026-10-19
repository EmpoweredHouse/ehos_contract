defmodule Rehmed.PayerPeriodRaceTest do
  @moduledoc """
  E9's acceptance for the boundary, on the client's own contract rather than an
  invented one: **in a race over one payer's period the invariant never breaks,
  and the conflict check reads only a range of the primary key.**

  The invariant is `Rehmed.Contracts.ExternalPayers`' — a period is invoiced only
  when every visit charged to the payer in it is marked settled with the payer or
  excluded. The race is reception closing and marking visits at the desk while the
  manager invoices. Everything here commits, on `EhOsContractHost.CommitRepo`, with
  the engine's `:repo` pointed at it for the test: the sandbox's own repo gives each
  test one connection, which serialises every dispatch.
  """

  use ExUnit.Case, async: false

  import Ecto.Query

  alias EhOsContract.{Actor, Event, Rejection, Store}
  alias EhOsContractHost.CommitRepo, as: Repo
  alias Rehmed.Contracts.{ExternalPayers, Settlement}
  alias Rehmed.Contracts.ExternalPayers.Commands.{IssuePayerInvoice, MarkSettledWithPayer}
  alias Rehmed.Contracts.Settlement.Commands.CloseSettlement

  @period "2026-09"

  @reception Actor.credential("reception-ola", [
               "rehmed.close_settlement",
               "rehmed.mark_settled_with_payer"
             ])
  @manager Actor.credential("manager-radek", ["rehmed.issue_payer_invoice"])

  setup do
    previous = Application.fetch_env!(:eh_os_contract, :repo)
    Application.put_env(:eh_os_contract, :repo, Repo)
    on_exit(fn -> Application.put_env(:eh_os_contract, :repo, previous) end)
    %{payer: "payer-race-#{System.unique_integer([:positive])}"}
  end

  # A visit is a settlement stream of its own and the log keeps it across tests, so
  # its identifier carries the test's payer.
  defp close(payer, visit) do
    EhOsContract.dispatch(
      Settlement,
      %CloseSettlement{
        visit_id: "#{payer}-#{visit}",
        total: 18_000,
        payer_id: payer,
        period_id: @period
      },
      actor: @reception
    )
  end

  defp mark(payer, visit) do
    EhOsContract.dispatch(
      ExternalPayers,
      %MarkSettledWithPayer{payer_id: payer, period_id: @period, visit_id: "#{payer}-#{visit}"},
      actor: @reception
    )
  end

  defp invoice(payer) do
    EhOsContract.dispatch(
      ExternalPayers,
      %IssuePayerInvoice{payer_id: payer, period_id: @period, invoice_id: "invoice-#{payer}"},
      actor: @manager
    )
  end

  # This payer's events in the log, in the order they were appended.
  defp log(payer) do
    Repo.all(
      from(e in Event,
        where: fragment("? @> ?::text[]", e.tags, ^["payer_id:#{payer}"]),
        order_by: e.position,
        select: {e.type, e.payload}
      )
    )
  end

  test "a visit charged while the invoice waits to append: the invoice is decided again, and refused",
       %{payer: payer} do
    {:ok, _} = close(payer, "visit-anna")
    {:ok, _} = mark(payer, "visit-anna")
    parent = self()

    # Holds the append lock, so the invoice reads its boundary, decides on Anna's
    # visit alone, and waits to append; Ben's visit is charged under the same lock.
    holder =
      Task.async(fn ->
        Repo.transaction(fn ->
          :ok = Store.lock(Repo)
          send(parent, :locked)

          receive do
            :charge -> {:ok, _} = close(payer, "visit-ben")
          end
        end)
      end)

    assert_receive :locked
    manager = Task.async(fn -> invoice(payer) end)
    wait_for_a_writer_blocked_on_the_lock()
    send(holder.pid, :charge)
    assert {:ok, {:ok, _}} = Task.await(holder)

    assert {:error, %Rejection{invariant: :every_delivered_visit_settled_or_excluded}} =
             Task.await(manager)

    refute Enum.any?(log(payer), fn {type, _} -> type =~ "payer_invoice_issued" end)
  end

  test "ten visits closed and marked at the desk while the manager invoices: no invoice leaves a charged visit unmarked",
       %{payer: payer} do
    desk =
      for n <- 1..10 do
        Task.async(fn -> settle_at_the_desk(payer, "visit-#{n}") end)
      end

    manager = Task.async(fn -> invoice_until_issued(payer, 200) end)
    Enum.each(desk, &Task.await(&1, 60_000))
    assert {:ok, _} = Task.await(manager, 60_000)

    events = log(payer)
    {before, [_invoice | _after]} = Enum.split_while(events, &(not issued?(&1)))

    visits = fn suffix ->
      for {type, p} <- before, type =~ suffix, into: MapSet.new(), do: p["visit_id"]
    end

    # An invoice needs a marked visit, so it cannot have gone out before the race began.
    assert MapSet.size(visits.("visit_charged_to_payer")) > 0

    assert MapSet.subset?(
             visits.("visit_charged_to_payer"),
             visits.("visit_marked_settled_with_payer")
           )

    assert Enum.count(events, &issued?/1) == 1
  end

  defp issued?({type, _payload}), do: type =~ "payer_invoice_issued"

  # Reception closes the visit, which charges the payer, and marks it at the
  # payer's: two dispatches, with a moment between them in which the visit is
  # charged and not yet marked. A mark after the invoice is refused, which is the
  # contract's answer and not the test's concern.
  defp settle_at_the_desk(payer, visit) do
    {:ok, _} = close(payer, visit)
    until_settled(fn -> mark(payer, visit) end, 20)
  end

  # The manager tries again while nothing is marked yet or a charged visit is
  # unmarked, as the monthly screen would be opened again once reception catches up.
  defp invoice_until_issued(_payer, 0), do: flunk("the invoice was never issued")

  defp invoice_until_issued(payer, tries) do
    case until_settled(fn -> invoice(payer) end, 20) do
      {:ok, _} = issued ->
        issued

      {:error, %Rejection{invariant: invariant}}
      when invariant in [
             :an_invoice_covers_a_marked_visit,
             :every_delivered_visit_settled_or_excluded
           ] ->
        Process.sleep(5)
        invoice_until_issued(payer, tries - 1)
    end
  end

  # Dispatch retries a conflict three times; one whose three all met another writer
  # is sent again, as a host would, a bounded number of times.
  defp until_settled(_send, 0), do: flunk("a dispatch kept conflicting")

  defp until_settled(send, sends) do
    case send.() do
      {:error, :conflict} -> until_settled(send, sends - 1)
      settled -> settled
    end
  end

  test "the invoice's conflict check reads the log after the head, by the primary key",
       %{payer: payer} do
    {:ok, _} = close(payer, "visit-anna")
    {:ok, _} = mark(payer, "visit-anna")

    # The check is the statement the store runs under the lock, captured as it runs
    # and explained with its own parameters, on a table with statistics, as
    # autovacuum keeps a real one. Without them the planner guesses a third of the
    # table for `position > head`, and on this table it served one of the consulted
    # types by the index of `type` alone, reading that type's whole history (plan,
    # E9b). Sequential scans are switched off because the table is small enough for
    # the planner to prefer one whatever the indexes: what is asserted is which
    # index serves the check.
    parent = self()
    handler = "payer-period-explain-#{System.unique_integer([:positive])}"

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
      assert {:ok, _} = invoice(payer)
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
    do: flunk("the invoice never waited for the lock")

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
