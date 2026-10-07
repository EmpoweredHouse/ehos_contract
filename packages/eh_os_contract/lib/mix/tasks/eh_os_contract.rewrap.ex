defmodule Mix.Tasks.EhOsContract.Rewrap do
  @shortdoc "Rewraps the subjects' data keys with the vault's current master key"

  @moduledoc """
  Rewraps every subject's data key that a master key other than the vault's current
  one wraps, so that an old master key can be retired.

      mix eh_os_contract.rewrap

  How a master key is rotated (`EhOsContract.Vault`): put the new key first in the
  vault's list, keep the old one after it, deploy, run this, and only then drop the
  old key. No event is rewritten; each data key is unwrapped with the key that
  wrapped it and wrapped again. It runs in batches of 500, each its own transaction,
  so it can be stopped and run again.
  """

  use Boundary, classify_to: EhOsContract
  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")
    repo = EhOsContract.Config.fetch!(:repo)
    count = EhOsContract.Personal.rewrap!(repo)
    Mix.shell().info("#{count} data keys rewrapped with #{EhOsContract.Vault.current()}")
  end
end
