defmodule DispatchRig.LinesOf do
  @moduledoc "**Invented.** One account's ledger lines, in the log's order."

  use DispatchRig.Ledger, query: :lines_of

  import Ecto.Query

  @impl true
  def lines_of(%LinesOf{account_id: id}, _ctx) do
    for {account, amount} <-
          Application.fetch_env!(:eh_os_contract, :repo).all(
            from(l in "dispatch_rig_lines",
              where: l.account_id == ^id,
              order_by: l.position,
              select: {l.account_id, l.amount}
            )
          ),
        do: %Row{account_id: account, amount: amount}
  end
end
