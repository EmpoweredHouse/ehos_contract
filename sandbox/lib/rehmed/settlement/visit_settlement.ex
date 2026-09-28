defmodule Rehmed.Settlement.VisitSettlement do
  @moduledoc """
  Decides the commercial side of one visit (`AGG-03`): `K5-20`'s two invariants on
  the handover, invariant 1 — payment lines sum to the total — and invariant 4: once
  closed, a settlement changes only by a correction.

  ## The partial-payment assumption, stated because it is ours

  Zero payments is a legitimate close: `C-30`'s close without payment is a real
  transition, and `P-08` exists to notice it. Anything other than zero must match
  the total exactly. What nobody described is a **partial** payment, 150 against
  200 with the rest owed. It is refused rather than modelled, because a settlement
  that can be short is a receivable, and receivables are `AGG-20`'s. If the clinic
  does take part payments, this is the clause that is wrong.
  """

  use Rehmed.Contracts.Settlement, aggregate: :visit_settlement

  @impl true
  def add_service_line(_command, %State{closed_on: %Date{}}),
    do: reject(:closed_settlement_changes_only_by_correction)

  def add_service_line(%AddServiceLine{visit_id: id, service_id: s}, _state),
    do: emit(%ServiceLineAdded{visit_id: id, service_id: s})

  @impl true
  def hand_over_visit(%HandOverVisit{visit_id: id}, %State{scope_changed: true}),
    do: emit(%VisitHandedOver{visit_id: id})

  def hand_over_visit(_command, _state), do: reject(:handover_only_after_scope_change)

  @impl true
  def record_payment(_command, %State{closed_on: %Date{}}),
    do: reject(:closed_settlement_changes_only_by_correction)

  def record_payment(%RecordPayment{visit_id: id, method: m, amount: a}, _state),
    do: emit(%PaymentRecorded{visit_id: id, method: m, amount: a})

  @impl true
  def close_settlement(_command, %State{closed_on: %Date{}}),
    do: reject(:closed_settlement_changes_only_by_correction)

  def close_settlement(_command, %State{scope_changed: true, handed_over: false}),
    do: reject(:changed_scope_handed_over_before_settlement)

  def close_settlement(%CloseSettlement{payer_id: payer, period_id: period}, _state)
      when is_nil(payer) != is_nil(period),
      do: reject(:payer_visit_names_its_period)

  # A visit no payer covers charges nobody; a mixed one is paid for the rest (`P-31`).
  def close_settlement(%CloseSettlement{} = close, %State{payments: paid}) do
    %CloseSettlement{visit_id: id, total: total, payer_id: payer, period_id: period} = close

    case {Enum.sum(paid), payer} do
      {0, nil} ->
        emit(%VisitClosedWithoutPayment{visit_id: id, total: total})

      {0, _payer} ->
        emit([
          %VisitClosedWithoutPayment{visit_id: id, total: total},
          %VisitChargedToPayer{visit_id: id, payer_id: payer, period_id: period}
        ])

      {^total, nil} ->
        emit(%VisitClosedCommercially{visit_id: id, total: total})

      {^total, _payer} ->
        emit([
          %VisitClosedCommercially{visit_id: id, total: total},
          %VisitChargedToPayer{visit_id: id, payer_id: payer, period_id: period}
        ])

      _short_or_over ->
        reject(:payment_lines_sum_to_total)
    end
  end

  # The day a correction belongs to is the close's, never the day it was entered,
  # which is the incumbent's defect. Before a close there is no day, and dispatch
  # refuses the event this decides (F2 in v2 §16).
  @impl true
  def book_correction(%BookCorrection{visit_id: id, delta: d}, %State{closed_on: day}),
    do: emit(%SettlementCorrected{visit_id: id, delta: d, business_date: day})

  @impl true
  def evolve(state, %ServiceLineAdded{}), do: %{state | scope_changed: true}
  def evolve(state, %VisitHandedOver{}), do: %{state | handed_over: true}
  def evolve(state, %PaymentRecorded{amount: a}), do: %{state | payments: [a | state.payments]}

  def evolve(state, %VisitClosedCommercially{__meta__: m}),
    do: %{state | closed_on: DateTime.to_date(m.occurred_at)}

  def evolve(state, %VisitClosedWithoutPayment{__meta__: m}),
    do: %{state | closed_on: DateTime.to_date(m.occurred_at)}

  def evolve(state, _changes_nothing), do: state
end
