defmodule EhosContract.Migrations.V06 do
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
  # when the two share a schema, as `EhosContract.Migrations` tells a host to set them.
  # Where they differ, or Oban runs another notifier, the notification reaches no one,
  # and the poll still finds the append.
  #
  # One notification per statement, and Postgres folds the identical notifications of
  # one transaction into one, so a transaction that appends many events wakes the
  # runners once.
  #
  # The cost: at commit, `NOTIFY` takes one lock for the whole Postgres instance and
  # holds it through the commit's flush, so every transaction that notifies — another
  # application's log on the same instance, Oban's own notifications — commits one
  # after another. Within one log the append lock already orders the commits; across
  # logs this brings back at commit some of what the per-schema append lock removed
  # (issue #51). Accepted at the scale of an EHOS application (#635).
  #
  # Two cases notify nothing and leave the append to the poll. A channel of 64 bytes or
  # more (a schema name of 44 bytes or more): `pg_notify` refuses it in the statement,
  # and the insert would fail with it. A notification queue half full: a listener that
  # stopped reading fills it until every commit that notifies is refused, and the commit
  # would fail; the half leaves room for the queue to grow between the insert and the
  # commit, and is where Postgres starts to warn. Reading the queue's usage takes the
  # queue's own locks for a moment, in the statement, to advance its tail.

  use Ecto.Migration

  @doc false
  @spec up() :: :ok
  def up do
    execute """
    CREATE FUNCTION eh_os_contract_events_notify() RETURNS trigger LANGUAGE plpgsql AS
    $$ DECLARE
      channel text := TG_TABLE_SCHEMA || '.oban_eh_os_contract';
    BEGIN
      IF pg_catalog.octet_length(channel) < 64
         AND pg_catalog.pg_notification_queue_usage() < 0.5 THEN
        PERFORM pg_catalog.pg_notify(channel, '{}');
      END IF;
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
