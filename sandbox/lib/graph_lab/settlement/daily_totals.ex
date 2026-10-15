defmodule GraphLab.Settlement.DailyTotals do
  @moduledoc """
  Projects the day's payments per method (`R-07`) into `graph_lab_daily_payments`: one
  row per payment, keyed by the event, so a second delivery writes nothing. The day is
  the clinic's, in Warsaw. The query sums them.
  """

  use GraphLab.Contracts.Settlement, read_model: :daily_totals

  @table "graph_lab_daily_payments"

  @impl true
  def payment_recorded(%PaymentRecorded{method: method, amount: amount, __meta__: meta}) do
    repo().insert_all(
      @table,
      [
        %{
          event_id: Ecto.UUID.dump!(meta.id),
          business_date:
            meta.occurred_at |> DateTime.shift_zone!("Europe/Warsaw") |> DateTime.to_date(),
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
