defmodule Rehmed.SettlementDispatchTest do
  @moduledoc """
  `Rehmed.Contracts.Settlement` dispatched in the host that consumes the library:
  the capabilities are named after the domain, the implementations are found in
  this application, the events land in its log, and `R-07` is projected in the
  dispatch's transaction and read back by its query.
  """

  use EhOsContractHost.DataCase, async: false

  alias EhOsContract.{Actor, Clock, Event, Rejection}
  alias Rehmed.Contracts.Settlement

  alias Rehmed.Contracts.Settlement.Commands.{
    AddServiceLine,
    BookCorrection,
    CloseSettlement,
    HandOverVisit,
    RecordPayment
  }

  alias Rehmed.Contracts.Settlement.Queries.DailyTotalsFor

  @specialist Actor.credential("specialist-ewa", [
                "rehmed.add_service_line",
                "rehmed.hand_over_visit"
              ])
  @reception Actor.credential("reception-ola", [
               "rehmed.record_payment",
               "rehmed.close_settlement",
               "rehmed.book_correction",
               "rehmed.daily_totals_for"
             ])

  defp types, do: Repo.all(from(e in Event, order_by: e.position, select: e.type))

  defp pay(visit, method, amount) do
    {:ok, _} =
      EhOsContract.dispatch(
        Settlement,
        %RecordPayment{visit_id: visit, method: method, amount: amount},
        actor: @reception
      )
  end

  test "a visit whose scope did not change is paid in two lines and closed, with no handover" do
    pay("visit-anna", :card, 15_000)
    pay("visit-anna", :cash, 5_000)

    assert {:ok, _} =
             EhOsContract.dispatch(
               Settlement,
               %CloseSettlement{visit_id: "visit-anna", total: 20_000},
               actor: @reception
             )

    assert types() == [
             "rehmed.settlement.payment_recorded",
             "rehmed.settlement.payment_recorded",
             "rehmed.settlement.visit_closed_commercially"
           ]
  end

  test "K5-20: a changed scope is settled only after the specialist hands it over" do
    {:ok, _} =
      EhOsContract.dispatch(
        Settlement,
        %AddServiceLine{visit_id: "visit-ben", service_id: "service-ultrasound"},
        actor: @specialist
      )

    pay("visit-ben", :card, 20_000)
    close = %CloseSettlement{visit_id: "visit-ben", total: 20_000}

    assert EhOsContract.dispatch(Settlement, close, actor: @reception) ==
             {:error, %Rejection{invariant: :changed_scope_handed_over_before_settlement}}

    {:ok, _} =
      EhOsContract.dispatch(Settlement, %HandOverVisit{visit_id: "visit-ben"}, actor: @specialist)

    assert {:ok, _} = EhOsContract.dispatch(Settlement, close, actor: @reception)
  end

  test "a short payment is refused on the invariant, and a specialist may not take payments" do
    pay("visit-cara", :card, 15_000)

    assert EhOsContract.dispatch(
             Settlement,
             %CloseSettlement{visit_id: "visit-cara", total: 20_000},
             actor: @reception
           ) == {:error, %Rejection{invariant: :payment_lines_sum_to_total}}

    assert EhOsContract.dispatch(
             Settlement,
             %RecordPayment{visit_id: "visit-cara", method: :card, amount: 5_000},
             actor: @specialist
           ) == {:error, :missing_capability}
  end

  test "F2: a correction entered days later belongs to the day of the close" do
    Clock.at(~U[2026-09-01 10:00:00Z], fn ->
      pay("visit-dan", :card, 20_000)

      {:ok, _} =
        EhOsContract.dispatch(
          Settlement,
          %CloseSettlement{visit_id: "visit-dan", total: 20_000},
          actor: @reception
        )
    end)

    {:ok, receipt} =
      Clock.at(~U[2026-09-05 16:00:00Z], fn ->
        EhOsContract.dispatch(
          Settlement,
          %BookCorrection{visit_id: "visit-dan", delta: -5_000},
          actor: @reception
        )
      end)

    assert [%{business_date: ~D[2026-09-01], delta: -5_000}] = receipt.events
  end

  test "R-07: the day's payments per method, a split counted on its own method" do
    Clock.at(~U[2026-09-01 10:00:00Z], fn ->
      pay("visit-anna", :card, 15_000)
      pay("visit-anna", :cash, 5_000)
      pay("visit-ben", :card, 10_000)
    end)

    Clock.at(~U[2026-09-02 10:00:00Z], fn -> pay("visit-cara", :card, 1_000) end)

    assert {:ok, rows} =
             EhOsContract.query(
               Settlement,
               %DailyTotalsFor{business_date: ~D[2026-09-01]},
               actor: @reception
             )

    assert Enum.map(rows, &{&1.method, &1.total}) == [card: 25_000, cash: 5_000]
  end
end
