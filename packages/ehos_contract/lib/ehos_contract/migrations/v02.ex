defmodule EhosContract.Migrations.V02 do
  @moduledoc false

  # What a command's decision read besides the command and the unit's history: the rows
  # of the entities it `reads:`, by the name each arrives under, encoded by their
  # fields' types (plan DD, T2a, #240). `NULL` for a command that reads nothing, and for
  # every row written before this version. Entities hold no personal data (D6), so
  # nothing here needs sealing or erasing.
  #
  # The first version after the cut (V01). V01 is no longer rewritten in place: since
  # 4 October 2026 an application has a database on it.

  use Ecto.Migration

  @doc false
  @spec up() :: :ok
  def up do
    alter table(:eh_os_contract_commands) do
      add :inputs, :map
    end

    :ok
  end

  @doc false
  @spec down() :: :ok
  def down do
    alter table(:eh_os_contract_commands) do
      remove :inputs
    end

    :ok
  end
end
