defmodule Lending.LoanTest do
  @moduledoc """
  A loan dispatched in the host, with the clock moved: the overdue chase reminds at the
  due date and every week after until the copy comes back, and a late fee's promise is
  kept by a payment or, the other way, by a waiver (`Lending.Processes.LateFee`).
  """

  use EhosContractHost.DataCase, async: false

  alias EhosContract.{Actor, Clock, Event, Testing, Trace}
  alias Lending.Contracts.Circulation
  alias Lending.Contracts.Circulation.Commands.{LendCopy, PayLateFee, ReturnCopy, WaiveLateFee}

  @lent ~U[2026-09-01 10:00:00Z]
  @due ~U[2026-09-22 17:00:00Z]
  @day 24 * 3600

  @librarian Actor.credential("librarian-una", [
               "lending.lend_copy",
               "lending.return_copy",
               "lending.pay_late_fee",
               "lending.waive_late_fee"
             ])

  # The first drain is the deploy: the chase subscribes before any copy is lent.
  setup do
    Testing.drain()
    :ok
  end

  defp at(moment, fun), do: Clock.at(moment, fun)
  defp later(days), do: DateTime.add(@due, days * @day)

  defp send!(command, moment),
    do:
      {:ok, _} =
        at(moment, fn -> EhosContract.dispatch(Circulation, command, actor: @librarian) end)

  defp lend(loan) do
    send!(
      %LendCopy{
        loan_id: loan,
        copy_id: "copy-#{loan}",
        member_id: "member-ada",
        card_id: "card-ada",
        due_at: @due
      },
      @lent
    )
  end

  defp drain(moment), do: at(moment, fn -> Testing.drain() end)

  defp notices(loan) do
    Repo.all(
      from(e in Event,
        where: e.type == "lending.circulation.overdue_notice_sent",
        where: fragment("? @> ?::text[]", e.tags, ^["loan_id:#{loan}"]),
        select: e.occurred_at
      )
    )
  end

  defp verdicts(opts),
    do: Trace.evaluate(Lending.Processes.LateFee, :settled_within_thirty_days, opts)

  test "nothing before the due date, a notice at it, and another a week after the due date" do
    lend("loan-1")

    drain(DateTime.add(@due, -60))
    assert notices("loan-1") == []

    # An hour late: the next reminder is still a week after the due date.
    drain(DateTime.add(@due, 3600))
    assert length(notices("loan-1")) == 1

    drain(later(6))
    assert length(notices("loan-1")) == 1

    drain(later(7) |> DateTime.add(60))
    assert length(notices("loan-1")) == 2
  end

  test "a loan due long ago is reminded once, and a week later, not once a missed week" do
    lend("loan-1")

    drain(later(70))
    assert length(notices("loan-1")) == 1

    drain(later(76))
    assert length(notices("loan-1")) == 1

    drain(later(77) |> DateTime.add(3600))
    assert length(notices("loan-1")) == 2
  end

  test "a copy back before its due date is never chased" do
    lend("loan-1")
    send!(%ReturnCopy{loan_id: "loan-1", late_fee: 0}, later(-2))

    drain(later(15))
    assert notices("loan-1") == []
  end

  test "a late fee waived keeps the promise the other way" do
    lend("loan-1")
    send!(%ReturnCopy{loan_id: "loan-1", late_fee: 150}, later(3))
    send!(%WaiveLateFee{loan_id: "loan-1"}, later(4))

    assert [%{verdict: :satisfied, via: :or_else}] = verdicts(now: later(40))
  end

  test "a late fee paid keeps it, and one left unsettled breaks it after thirty days" do
    lend("loan-1")
    send!(%ReturnCopy{loan_id: "loan-1", late_fee: 150}, later(3))
    send!(%PayLateFee{loan_id: "loan-1"}, later(10))

    lend("loan-2")
    send!(%ReturnCopy{loan_id: "loan-2", late_fee: 150}, later(3))

    assert [
             %{verdict: :satisfied, via: :eventually},
             %{verdict: :pending}
           ] = verdicts(now: later(20)) |> Enum.sort_by(& &1.verdict, :desc)

    assert Enum.map(verdicts(now: later(40)), & &1.verdict) |> Enum.sort() ==
             [:satisfied, :violated]
  end
end
