defmodule DispatchRig.AuditWithdrawal do
  @moduledoc """
  **Invented.** Audits a withdrawal inside the dispatch transaction. The audit is
  unavailable for a withdrawal of exactly 99, which exists only so that a test can
  watch an effect's error roll the append back.
  """

  use DispatchRig.Ledger, effect: :audit_withdrawal

  require Logger

  @impl true
  def withdrawn(%Withdrawn{amount: 99}), do: {:error, :audit_unavailable}

  # A line, so a test can see what the engine puts in the Logger's metadata (#298).
  def withdrawn(%Withdrawn{}), do: Logger.debug("audited a withdrawal")
end
