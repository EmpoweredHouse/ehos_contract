defmodule Taxvision.AccountingMonth.TurnoverMatching do
  @moduledoc """
  Matches one company's month: a statement becomes its list of turnovers, and a
  turnover is paired with an invoice KSeF gave for the month that no turnover has
  been paired with yet — which one is the domain service's to say. A turnover is
  decided once: a statement uploaded again does not decide it anew.
  """

  use Taxvision.Contracts.AccountingMonth, dcb: :turnover_matching

  alias Taxvision.Contracts.AccountingMonth.DomainServices.Pairing
  alias Taxvision.Contracts.DocumentIntake.Events.InvoicePulledFromKsef

  @impl true
  def ingest_bank_statement(%IngestBankStatement{} = c, _state),
    do:
      emit(%BankTurnoverListCreated{
        company_id: c.company_id,
        period_id: c.period_id,
        turnovers: c.turnovers
      })

  @impl true
  def run_matching(%RunMatching{turnover: turnover} = c, %State{} = state) do
    if turnover.turnover_id in state.decided do
      reject(:a_turnover_is_matched_once)
    else
      offered = state.invoices |> Enum.reverse() |> Enum.reject(&(&1.ksef_number in state.paired))

      case Pairing.invoice_for(turnover.amount_minor, offered) do
        nil ->
          emit(%TurnoverWithoutInvoiceFlagged{
            company_id: c.company_id,
            period_id: c.period_id,
            turnover_id: turnover.turnover_id
          })

        number ->
          emit(%TurnoverMatchedWithInvoice{
            company_id: c.company_id,
            period_id: c.period_id,
            turnover_id: turnover.turnover_id,
            ksef_number: number
          })
      end
    end
  end

  # Newest first, reversed when offered, so the pairing sees them in the order KSeF
  # gave them. An invoice pulled twice is offered once.
  @impl true
  def evolve(state, %InvoicePulledFromKsef{ksef_number: number, amount_minor: amount}) do
    if Enum.any?(state.invoices, &(&1.ksef_number == number)),
      do: state,
      else: %{state | invoices: [%{ksef_number: number, amount_minor: amount} | state.invoices]}
  end

  # What a turnover took is kept apart from what KSeF gave, so an invoice pulled
  # again after it paired is not offered again, whatever the order in the log.
  def evolve(state, %TurnoverMatchedWithInvoice{turnover_id: id, ksef_number: number}),
    do: %{state | paired: [number | state.paired], decided: [id | state.decided]}

  def evolve(state, %TurnoverWithoutInvoiceFlagged{turnover_id: id}),
    do: %{state | decided: [id | state.decided]}

  def evolve(state, _event), do: state
end
