defmodule Taxvision.AccountingMonth.Pairing do
  @moduledoc """
  The domain service `:pairing` (P7): the first invoice on the turnover's amount.
  By amount alone — the material's margin of days is not here.
  """

  use Taxvision.Contracts.AccountingMonth, domain_service: :pairing

  @impl true
  def invoice_for(amount_minor, invoices) do
    case Enum.find(invoices, &(&1.amount_minor == amount_minor)) do
      nil -> nil
      invoice -> invoice.ksef_number
    end
  end
end
