defmodule GraphLab.Settlement.VisitSettlement do
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

  use GraphLab.Contracts.Settlement, aggregate: :visit_settlement

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

  # A visit no payer covers charges nobody. A mixed one closes with the patient's part
  # as its total, paid, and charges the payer for the rest (`P-31`).
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

  # The chase's flag, which nothing refuses.
  @impl true
  def flag_unsettled_visit(%FlagUnsettledVisit{visit_id: id}, _state),
    do: emit(%UnsettledVisitFlagged{visit_id: id})

  # The day a correction belongs to is the close's, never the day it was entered,
  # which is the defect the rule exists for. Before a close there is no day, and
  # nothing to correct.
  @impl true
  def book_correction(_command, %State{closed_on: nil}),
    do: reject(:only_a_settled_visit_is_corrected)

  def book_correction(%BookCorrection{visit_id: id, delta: d}, %State{closed_on: day}),
    do: emit(%SettlementCorrected{visit_id: id, delta: d, business_date: day})

  # A service line, a payment or a second close after the close changes what was
  # settled, and is marked so `holds?/2` can say so; a handover changes no amount.
  @impl true
  def evolve(state, %ServiceLineAdded{}), do: after_close(%{state | scope_changed: true}, state)
  def evolve(state, %VisitHandedOver{}), do: %{state | handed_over: true}

  def evolve(state, %PaymentRecorded{amount: a}),
    do: after_close(%{state | payments: [a | state.payments]}, state)

  def evolve(state, %VisitClosedCommercially{total: total, __meta__: m}),
    do: after_close(%{state | closed_on: DateTime.to_date(m.occurred_at), total: total}, state)

  def evolve(state, %VisitClosedWithoutPayment{total: total, __meta__: m}),
    do: after_close(%{state | closed_on: DateTime.to_date(m.occurred_at), total: total}, state)

  def evolve(state, _changes_nothing), do: state

  defp after_close(next, %State{closed_on: nil}), do: next
  defp after_close(next, _closed), do: %{next | changed_after_close: true}

  @doc """
  Whether `state` keeps `invariant`, for the settlement's properties: what each of
  `AGG-03`'s invariants and `K5-20`'s two means of a state the decisions reached.
  """
  @spec holds?(atom(), State.t()) :: boolean()
  def holds?(:handover_only_after_scope_change, state),
    do: not state.handed_over or state.scope_changed

  def holds?(:changed_scope_handed_over_before_settlement, state),
    do: state.closed_on == nil or not state.scope_changed or state.handed_over

  # Payments summing to nothing close without payment, as the decider reads them (the
  # moduledoc); any other sum is the total.
  def holds?(:payment_lines_sum_to_total, state),
    do: state.closed_on == nil or Enum.sum(state.payments) in [0, state.total]

  def holds?(:closed_settlement_changes_only_by_correction, state),
    do: not state.changed_after_close

  # The state keeps no correction, so nothing here to check: the decision refuses one
  # before a close, which its scenario and the decision's property show.
  def holds?(:only_a_settled_visit_is_corrected, _state), do: true
end
