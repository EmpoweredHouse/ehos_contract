defmodule EhOsContract.Migrations.V06 do
  @moduledoc false

  # An insert into the log wakes the subscription runners when its transaction commits
  # (issue #635), also in a transaction the host's own code owns, which the engine does
  # not see commit. Before it, such an append waited for the runners' poll.
  #
  # The trigger notifies the channel that Oban's Postgres notifier listens on for the
  # runners, `"<prefix>.oban_eh_os_contract"`, with an empty JSON object. The notifier
  # hands it to each runner as `{:notification, :eh_os_contract, %{}}`, the message
  # dispatch already sends after its own commits, so nothing listens twice and no
  # connection is added. The prefix is the schema of the log, which is Oban's prefix
  # when the two share a schema, as `EhOsContract.Migrations` tells a host to set them.
  # Where they differ, or Oban runs another notifier, the notification reaches no one,
  # and the poll still finds the append.
  #
  # One notification per statement, and Postgres folds the identical notifications of
  # one transaction into one, so a transaction that appends many events wakes the
  # runners once. `NOTIFY` takes a lock on the database's notification queue at commit,
  # which serialises the commits of concurrent appenders; the append lock already
  # serialises the appends to one log.

  use Ecto.Migration

  @doc false
  @spec up() :: :ok
  def up do
    execute """
    CREATE FUNCTION eh_os_contract_events_notify() RETURNS trigger LANGUAGE plpgsql AS
    $$ BEGIN
      PERFORM pg_catalog.pg_notify(TG_TABLE_SCHEMA || '.oban_eh_os_contract', '{}');
      RETURN NULL;
    END $$
    """

    execute """
    CREATE TRIGGER eh_os_contract_events_notify
    AFTER INSERT ON eh_os_contract_events
    FOR EACH STATEMENT EXECUTE FUNCTION eh_os_contract_events_notify()
    """

    :ok
  end

  @doc false
  @spec down() :: :ok
  def down do
    execute "DROP TRIGGER eh_os_contract_events_notify ON eh_os_contract_events"
    execute "DROP FUNCTION eh_os_contract_events_notify()"
    :ok
  end
end
