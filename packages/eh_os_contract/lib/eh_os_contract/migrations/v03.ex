defmodule EhOsContract.Migrations.V03 do
  @moduledoc false

  # A contract no longer declares a process (plan DD, P2h, #221), so no event has a home
  # run and no command a run of its own. `process` and `instance_id` of the events and
  # the commands, written from a contract's process and never read since runs moved to
  # `eh_os_contract_event_runs`, go. Every run an event belongs to is a row there, filed
  # under the process module that includes it.
  #
  # The first version that removes: a node of an older release would fail on every
  # append, writing a column that is gone, so `EhOsContract.Migrations.check!/1` refuses
  # to start on storage newer than its own. `down/0` gives the columns back empty,
  # nullable as they always were; what they held is not restored.

  use Ecto.Migration

  @doc false
  @spec up() :: :ok
  def up do
    for table <- [:eh_os_contract_events, :eh_os_contract_commands] do
      alter table(table) do
        remove :process
        remove :instance_id
      end
    end

    :ok
  end

  @doc false
  @spec down() :: :ok
  def down do
    for table <- [:eh_os_contract_events, :eh_os_contract_commands] do
      alter table(table) do
        add :process, :text
        add :instance_id, :text
      end
    end

    :ok
  end
end
