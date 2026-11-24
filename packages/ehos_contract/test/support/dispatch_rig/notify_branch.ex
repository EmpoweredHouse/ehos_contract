defmodule DispatchRig.NotifyBranch do
  @moduledoc """
  **Invented.** Tells the branch an account was flagged, by writing a notice keyed by
  the event's id, so a second delivery writes nothing twice. The branch of account
  `"a-down"` is unreachable.
  """

  use DispatchRig.Ledger, effect: :notify_branch

  require Logger

  @impl true
  def account_flagged(%AccountFlagged{account_id: "a-down"}), do: {:error, :branch_unreachable}

  def account_flagged(%AccountFlagged{account_id: id, __meta__: meta}) do
    Application.fetch_env!(:ehos_contract, :repo).insert_all(
      "dispatch_rig_notices",
      [%{event_id: Ecto.UUID.dump!(meta.id), account_id: id}],
      on_conflict: :nothing
    )

    # A line, so a test can see what the engine puts in the Logger's metadata (#298).
    Logger.debug("notified the branch")
  end
end
