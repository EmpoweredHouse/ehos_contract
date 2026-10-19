defmodule Billing.Subscriptions.Invoice do
  @moduledoc """
  **Invented.** Decides an invoice: each line added once, and the invoice issued once,
  for the sum of its lines, only when it has some, and only when the sum fits in an
  amount.
  """

  use Billing.Contracts.Subscriptions, aggregate: :invoice

  # An amount is a 64-bit integer of cents.
  @largest_amount 9_223_372_036_854_775_807

  @impl true
  def add_invoice_line(_command, %State{issued: true}), do: reject(:issued_once_with_lines)

  def add_invoice_line(%AddInvoiceLine{} = line, %State{} = state) do
    cond do
      line.line_id in state.lines ->
        reject(:line_added_once)

      state.total + line.amount > @largest_amount ->
        reject(:total_fits_an_amount)

      true ->
        emit(%LineAdded{
          subscription_id: line.subscription_id,
          period_id: line.period_id,
          line_id: line.line_id,
          amount: line.amount
        })
    end
  end

  @impl true
  def issue_invoice(_command, %State{issued: true}), do: reject(:issued_once_with_lines)
  def issue_invoice(_command, %State{lines: []}), do: reject(:issued_once_with_lines)

  # Lines added by `add_invoice_line/2` cannot sum past it; a history from elsewhere, as
  # the properties generate, can.
  def issue_invoice(_command, %State{total: total}) when total > @largest_amount,
    do: reject(:total_fits_an_amount)

  def issue_invoice(%IssueInvoice{subscription_id: id, period_id: period}, %State{total: total}),
    do: emit(%Issued{subscription_id: id, period_id: period, total: total})

  @impl true
  def evolve(state, %LineAdded{line_id: line, amount: amount}),
    do: %{state | lines: [line | state.lines], total: state.total + amount}

  def evolve(state, %Issued{}), do: %{state | issued: true}
end
