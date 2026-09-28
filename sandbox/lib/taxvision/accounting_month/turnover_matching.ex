defmodule Taxvision.AccountingMonth.TurnoverMatching do
  @moduledoc """
  Matches one company's month: a statement becomes its list of turnovers, and a
  turnover is paired with an invoice KSeF gave for the month that no turnover has
  been paired with yet — which one is the domain service's to say.
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
  def run_matching(%RunMatching{turnover: turnover} = c, %State{invoices: invoices}) do
    case Pairing.invoice_for(turnover.amount_minor, invoices) do
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

  @impl true
  def evolve(state, %InvoicePulledFromKsef{ksef_number: number, amount_minor: amount}),
    do: %{state | invoices: state.invoices ++ [%{ksef_number: number, amount_minor: amount}]}

  # An invoice pairs once: the one a turnover took is no longer offered.
  def evolve(state, %TurnoverMatchedWithInvoice{ksef_number: number}),
    do: %{state | invoices: Enum.reject(state.invoices, &(&1.ksef_number == number))}

  def evolve(state, _event), do: state
end
