defmodule Rehmed.ExternalPayers.PayerPeriod do
  @moduledoc """
  Decides one payer's period (`AGG-11`): an invoice only when every visit charged to
  the payer in the period is marked settled with the payer or excluded with a
  reason, and nothing in the period after its invoice.

  The state is what the boundary read: the visits settlement charged to this payer
  in this period, and this period's own marks, exclusions and invoice. Dispatch
  decides again when any of them was appended after the read, so the refusal holds
  while reception is still closing visits.
  """

  use Rehmed.Contracts.ExternalPayers, dcb: :payer_period

  alias Rehmed.Contracts.Settlement.Events.VisitChargedToPayer

  @impl true
  def mark_settled_with_payer(_command, %State{invoiced: true}),
    do: reject(:invoiced_period_does_not_change)

  def mark_settled_with_payer(%MarkSettledWithPayer{} = mark, %State{} = state) do
    %MarkSettledWithPayer{payer_id: payer, period_id: period, visit_id: visit} = mark

    if open?(state, visit),
      do: emit(%VisitMarkedSettledWithPayer{payer_id: payer, period_id: period, visit_id: visit}),
      else: reject(:only_a_charged_visit_is_marked_or_excluded)
  end

  @impl true
  def exclude_visit_from_invoice(_command, %State{invoiced: true}),
    do: reject(:invoiced_period_does_not_change)

  def exclude_visit_from_invoice(%ExcludeVisitFromInvoice{} = exclusion, %State{} = state) do
    %ExcludeVisitFromInvoice{payer_id: payer, period_id: period, visit_id: visit, reason: why} =
      exclusion

    if open?(state, visit) do
      emit(%VisitExcludedFromInvoice{
        payer_id: payer,
        period_id: period,
        visit_id: visit,
        reason: why
      })
    else
      reject(:only_a_charged_visit_is_marked_or_excluded)
    end
  end

  # Charged to this payer in this period, and neither marked nor excluded yet.
  defp open?(%State{} = state, visit),
    do: visit in state.charged and visit not in state.marked and visit not in state.excluded

  @impl true
  def issue_payer_invoice(_command, %State{invoiced: true}),
    do: reject(:invoiced_period_does_not_change)

  def issue_payer_invoice(%IssuePayerInvoice{} = invoice, %State{} = state) do
    %IssuePayerInvoice{payer_id: payer, period_id: period, invoice_id: number} = invoice

    if Enum.all?(state.charged, &(&1 in state.marked or &1 in state.excluded)),
      do: emit(%PayerInvoiceIssued{payer_id: payer, period_id: period, invoice_id: number}),
      else: reject(:every_delivered_visit_settled_or_excluded)
  end

  @impl true
  def evolve(state, %VisitChargedToPayer{visit_id: v}),
    do: %{state | charged: [v | state.charged]}

  def evolve(state, %VisitMarkedSettledWithPayer{visit_id: v}),
    do: %{state | marked: [v | state.marked]}

  def evolve(state, %VisitExcludedFromInvoice{visit_id: v}),
    do: %{state | excluded: [v | state.excluded]}

  def evolve(state, %PayerInvoiceIssued{}), do: %{state | invoiced: true}
end
