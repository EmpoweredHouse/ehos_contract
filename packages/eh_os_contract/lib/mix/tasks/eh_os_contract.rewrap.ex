defmodule Mix.Tasks.EhOsContract.Rewrap do
  @shortdoc "Rewraps the data keys of the subjects with the current master key"

  @moduledoc """
  Rewraps each data key that an old master key wraps, with the current master key
  of the vault. Run it in step 3 of
  [a rotation](master-keys.md#rotate-a-master-key), before you remove the old key.

  > **The task starts the whole application.**
  > Run it only with the code that is deployed. The task records a deployment, and
  > starts the subscriptions, the relays and Oban. So effects can call external
  > systems from where you run it. If your code differs from the deployed code, the
  > engine rebuilds each changed process manager at once. It also rebuilds each
  > changed read model that has `reset/0`. A rebuilt process manager forgets its runs.

      mix eh_os_contract.rewrap

  The task unwraps each data key with the key that wrapped it, and wraps it again.
  It does not rewrite an event. At the end, it prints the count and the id of the
  key that it used:

      120 data keys rewrapped with 2026-09

  > **The printed id must be the id of the new key.**
  > The task wraps with the first key of the list that it reads.
  > With the configuration of before the rotation, it wraps each data key with the old
  > key again, and ends without an error. Remove the old key only when the printed id
  > is the id of the new key, and each row of `eh_os_contract_subject_keys` names it.
  > [Rotate a master key](master-keys.md#rotate-a-master-key) gives each step.

  - The task works in batches of 500 data keys. Each batch is a transaction of its
    own. If the task stops, run it again.
  - Each batch skips the rows that another run holds.
  - If a data key of another master key is left at the end, the task raises. Another
    run holds that key, or a node wrote it with the old key during the run. Run the
    task again when each node runs the new configuration.
  - If the vault does not hold the key that wraps a row, the task raises. Put that
    key back in the list, deploy, and run the task again.
  - Do not remove the old key while the task raises.
    [What can go wrong](master-keys.md#what-can-go-wrong) gives each message.
  - An erasure of a subject in the current batch waits for that batch. It holds the
    append lock while it waits, so each other append waits too. Run the task at a
    quiet time.
  - A release has no `mix`. From a release, call `EhOsContract.Personal.rewrap!/2`.
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
