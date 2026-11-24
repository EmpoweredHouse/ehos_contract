defmodule DispatchRig.LedgerLines do
  @moduledoc """
  **Invented.** One line per deposit and withdrawal, projected after the dispatch
  transaction, keyed by the event's position. It raises on a deposit of exactly 31,
  which exists only so that a test can watch a poison event stop an ordered consumer,
  and takes 200 ms over a deposit of 500, so that a test can hold a batch while
  another runner asks for it.
  """

  use DispatchRig.Ledger, read_model: :ledger_lines

  @impl true
  def deposited(%Deposited{amount: 31}), do: raise("the ledger lines fail on 31")

  def deposited(%Deposited{account_id: id, amount: amount, __meta__: meta}) do
    if amount == 500, do: Process.sleep(200)
    line(id, amount, meta.position)
  end

  @impl true
  def withdrawn(%Withdrawn{account_id: id, amount: amount, __meta__: meta}),
    do: line(id, -amount, meta.position)

  @impl true
  def reset do
    repo().delete_all("dispatch_rig_lines")
    :ok
  end

  defp line(id, amount, position) do
    repo().insert_all("dispatch_rig_lines", [
      %{position: position, account_id: id, amount: amount}
    ])

    :ok
  end

  defp repo, do: Application.fetch_env!(:ehos_contract, :repo)
end
