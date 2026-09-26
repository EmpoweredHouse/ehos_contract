defmodule Rehmed.Settlement.VisitSettlement do
  @moduledoc """
  Decides the commercial side of one visit (v2 §4.5). It encodes `AGG-03` invariant
  1 and nothing beyond it — *payment lines sum to the settlement total* — because
  that invariant is stated, and its failure is on record: split payments flip sign
  in the incumbent, so the daily report is wrong on exactly the days it matters
  (W1 02:02:07).

  ## The partial-payment assumption, stated because it is ours

  Zero payments is a legitimate close: `C-30`'s close without payment is a real
  transition, and `P-08` exists to notice it. Anything other than zero must match
  the total exactly.

  What nobody described is a **partial** payment — 150 against a total of 200, with
  the rest owed. It is refused here rather than modelled, because a settlement that
  can be short is a receivable, and receivables are `AGG-20`'s subject, which has
  its own lifecycle and is not this. If the clinic does take part payments, this is
  the clause that is wrong.

  The total comes with the handover (F1) and a correction's day is the handover's
  (F2): both are in the contract's moduledoc.
  """

  use Rehmed.Contracts.VisitSettlement, aggregate: :visit_settlement

  @impl true
  def add_service_line(%AddServiceLine{visit_id: id, service_id: s}, _state),
    do: emit(%ServiceLineAdded{visit_id: id, service_id: s})

  @impl true
  def hand_over_visit(%HandOverVisit{visit_id: id, total: total}, _state),
    do: emit(%VisitHandedOver{visit_id: id, total: total})

  @impl true
  def record_payment(%RecordPayment{visit_id: id, method: m, amount: a}, _state),
    do: emit(%PaymentRecorded{visit_id: id, method: m, amount: a})

  @impl true
  def close_settlement(%CloseSettlement{visit_id: id}, %State{total: total, payments: paid}) do
    case Enum.sum(paid) do
      0 -> emit(%VisitClosedWithoutPayment{visit_id: id})
      ^total -> emit(%VisitClosedCommercially{visit_id: id})
      _short_or_over -> reject(:payment_lines_sum_to_total)
    end
  end

  # F2: the day the correction belongs to is the handover's, never the day it was
  # entered, which is the incumbent's defect.
  @impl true
  def book_correction(%BookCorrection{visit_id: id, delta: d}, %State{handed_over_on: day}),
    do: emit(%SettlementCorrected{visit_id: id, delta: d, business_date: day})

  @impl true
  def evolve(state, %VisitHandedOver{total: t, __meta__: m}),
    do: %{state | total: t, handed_over_on: DateTime.to_date(m.occurred_at)}

  def evolve(state, %PaymentRecorded{amount: a}), do: %{state | payments: [a | state.payments]}
  def evolve(state, _changes_nothing), do: state
end
