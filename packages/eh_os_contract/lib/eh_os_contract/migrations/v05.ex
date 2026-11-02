defmodule EhOsContract.Migrations.V05 do
  @moduledoc false

  # A subscription that fails keeps the status it failed in, so that skipping the event
  # goes back to it (issue #550): `rebuilding` for a read model delivered in the
  # transaction or a process manager that failed while they replayed the log, `stale`
  # or `running` otherwise. Before it, a skip always went back to `running`, which ended
  # a rebuild at the skipped event. `NULL` in a row that is not failing, and in one that
  # was failing before this version, which a skip reads as `running`, as it did then.

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
