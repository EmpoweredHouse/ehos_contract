defmodule Rehmed.VisitSettlementDispatchTest do
  @moduledoc """
  `Rehmed.Contracts.VisitSettlement` dispatched in the host that consumes the
  library (v2 plan, E6): the capabilities are named after the domain, the
  implementation is found in this application, and the events land in its log.
  """

  use Taxvision.DataCase, async: false

  alias EhOsContract.{Actor, Clock, Event, Rejection}
  alias Rehmed.Contracts.VisitSettlement

  alias Rehmed.Contracts.VisitSettlement.Commands.{
    BookCorrection,
    CloseSettlement,
    HandOverVisit,
    RecordPayment
  }

  @specialist Actor.credential("s-1", ["rehmed.hand_over_visit"])
  @reception Actor.credential("r-1", [
               "rehmed.record_payment",
               "rehmed.close_settlement",
               "rehmed.book_correction"
             ])

  defp types, do: Repo.all(from(e in Event, order_by: e.position, select: e.type))

  test "a visit is handed over, paid in two lines and closed" do
    {:ok, _} =
      EhOsContract.dispatch(VisitSettlement, %HandOverVisit{visit_id: "w-1", total: 20_000},
        actor: @specialist
      )

    for {method, amount} <- [card: 15_000, cash: 5_000] do
      {:ok, _} =
        EhOsContract.dispatch(
          VisitSettlement,
          %RecordPayment{visit_id: "w-1", method: method, amount: amount},
          actor: @reception
        )
    end

    assert {:ok, _} =
             EhOsContract.dispatch(VisitSettlement, %CloseSettlement{visit_id: "w-1"},
               actor: @reception
             )

    assert types() == [
             "visit_settlement.visit_handed_over",
             "visit_settlement.payment_recorded",
             "visit_settlement.payment_recorded",
             "visit_settlement.visit_closed_commercially"
           ]
  end

  test "a short payment is refused on the invariant, and a specialist may not take payments" do
    {:ok, _} =
      EhOsContract.dispatch(VisitSettlement, %HandOverVisit{visit_id: "w-2", total: 20_000},
        actor: @specialist
      )

    {:ok, _} =
      EhOsContract.dispatch(
        VisitSettlement,
        %RecordPayment{visit_id: "w-2", method: :card, amount: 15_000},
        actor: @reception
      )

    assert EhOsContract.dispatch(VisitSettlement, %CloseSettlement{visit_id: "w-2"},
             actor: @reception
           ) ==
             {:error, %Rejection{invariant: :payment_lines_sum_to_total}}

    assert EhOsContract.dispatch(
             VisitSettlement,
             %RecordPayment{visit_id: "w-2", method: :card, amount: 5_000},
             actor: @specialist
           ) == {:error, :missing_capability}
  end

  test "F2: a correction entered days later belongs to the day of the handover" do
    Clock.at(~U[2026-09-01 10:00:00Z], fn ->
      {:ok, _} =
        EhOsContract.dispatch(VisitSettlement, %HandOverVisit{visit_id: "w-3", total: 20_000},
          actor: @specialist
        )
    end)

    {:ok, receipt} =
      Clock.at(~U[2026-09-05 16:00:00Z], fn ->
        EhOsContract.dispatch(VisitSettlement, %BookCorrection{visit_id: "w-3", delta: -5_000},
          actor: @reception
        )
      end)

    assert [%{business_date: ~D[2026-09-01], delta: -5_000}] = receipt.events
  end
end
