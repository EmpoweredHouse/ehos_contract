defmodule EhOsContract.Migrations.V02 do
  @moduledoc false

  # One digest per declaration on `eh_os_contract_deployments`, so a change to a single
  # declaration is attributable.
  #
  # **Nullable, and deliberately without a default.** A row written before this
  # column existed does not know what its contract declared, and `%{}` would claim
  # it declared nothing. That is a different statement, and the whole value of the
  # column is that `EhOsContract.Deployment.diff/2` can say "could not compare" instead of
  # "nothing changed". The distinction has to live in the column; a comment cannot
  # carry it into a query.

  use Ecto.Migration

  @doc false
  @spec up() :: :ok
  def up do
    alter table(:eh_os_contract_deployments) do
      add :declaration_digests, :map
    end

    :ok
  end

  @doc false
  @spec down() :: :ok
  def down do
    alter table(:eh_os_contract_deployments) do
      remove :declaration_digests
    end

    :ok
  end
end
