defmodule DispatchRig.AuditWithdrawal do
  @moduledoc """
  **Invented.** Audits a withdrawal inside the dispatch transaction. The audit is
  unavailable for a withdrawal of exactly 99, which exists only so that a test can
  watch an effect's error roll the append back.
  """

  use DispatchRig.Ledger, effect: :audit_withdrawal

  @impl true
  def withdrawn(%Withdrawn{amount: 99}), do: {:error, :audit_unavailable}
  def withdrawn(%Withdrawn{}), do: :ok
end
