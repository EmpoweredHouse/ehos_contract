defmodule DispatchRig.ReturnSmallChange do
  @moduledoc """
  **Invented.** After a withdrawal of exactly 3, deposits 1 back, after the fact. It
  exists so that a test can race an ordered policy's command against another writer
  of the same stream: a deposit sets off no effect, so nothing needs Oban.
  """

  use DispatchRig.Ledger, policy: :return_small_change

  @impl true
  def withdrawn(%Withdrawn{account_id: id, amount: 3}),
    do: issue(%Deposit{account_id: id, amount: 1})

  def withdrawn(_other), do: {:ok, []}
end
