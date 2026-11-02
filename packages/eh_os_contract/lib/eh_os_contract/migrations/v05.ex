defmodule EhOsContract.Migrations.V05 do
  @moduledoc false

  # A subscription that fails keeps the status it failed in, so that skipping the event
  # goes back to it (issue #550): `rebuilding` for a read model delivered in the
  # transaction or a process manager that failed while they replayed the log, `stale`
  # or `running` otherwise. Before it, a skip always went back to `running`, which ended
  # a rebuild at the skipped event. `NULL` in a row that is not failing, and in one that
  # was failing before this version, which a skip reads as `running`, as it did then.
  # Except a read model delivered in the transaction: it fails only while it is rebuilt,
  # and before this version dispatch went on projecting it while it was failing, so
  # neither status is true of its rows. It is marked `stale`, and the next boot rebuilds
  # it from the start; it has `reset/0`, since it was being rebuilt.

  use Ecto.Migration

  @doc false
  @spec up() :: :ok
  def up do
    alter table(:eh_os_contract_subscriptions) do
      add :resume_status, :text
    end

    create constraint(:eh_os_contract_subscriptions, :eh_os_contract_subscriptions_resume_status,
             check: "resume_status IN ('running', 'stale', 'rebuilding')"
           )

    execute("""
    UPDATE eh_os_contract_subscriptions SET status = 'stale'
    WHERE status = 'failing' AND mode = 'inline'
    """)

    :ok
  end

  @doc false
  @spec down() :: :ok
  def down do
    drop constraint(:eh_os_contract_subscriptions, :eh_os_contract_subscriptions_resume_status)

    alter table(:eh_os_contract_subscriptions) do
      remove :resume_status
    end

    :ok
  end
end
