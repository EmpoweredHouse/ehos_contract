defmodule GraphLab.Settlement.DailyTotalsFor do
  @moduledoc "Answers reception's `R-07`: the day's total per payment method."

  use GraphLab.Contracts.Settlement, query: :daily_totals_for

  import Ecto.Query

  @impl true
  def daily_totals_for(%DailyTotalsFor{business_date: day}, _ctx) do
    query =
      from(p in "rehmed_daily_payments",
        where: p.business_date == ^day,
        group_by: p.method,
        order_by: p.method,
        select: {p.method, type(sum(p.amount), :integer)}
      )

    for {method, total} <- EhOsContract.Config.fetch!(:repo).all(query),
        do: %Row{business_date: day, method: String.to_existing_atom(method), total: total}
  end
end
