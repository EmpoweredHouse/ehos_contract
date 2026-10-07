defmodule Rehmed.Settlement.DailyTotals do
  @moduledoc """
  Projects `R-07`, the day's payments per method, into `rehmed_daily_payments`: one
  row per payment, keyed by the event, so a second delivery writes nothing. The
  query sums them.
  """

  use Rehmed.Contracts.Settlement, read_model: :daily_totals

  @table "rehmed_daily_payments"

  @impl true
  def payment_recorded(%PaymentRecorded{method: method, amount: amount, __meta__: meta}) do
    repo().insert_all(
      @table,
      [
        %{
          event_id: Ecto.UUID.dump!(meta.id),
          business_date: DateTime.to_date(meta.occurred_at),
          method: Atom.to_string(method),
          amount: amount
        }
      ],
      on_conflict: :nothing
    )

    :ok
  end

  @impl true
  def reset do
    repo().delete_all(@table)
    :ok
  end

  defp repo, do: EhOsContract.Config.fetch!(:repo)
end
