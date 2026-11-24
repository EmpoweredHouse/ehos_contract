defmodule EhosContract.Migrations.V04 do
  @moduledoc false

  # A contract's version hashes what it allows, and its words have a digest of their own
  # (plan DD, V5, #322). A deployment records both, and a change of the words alone is a
  # row of its own, so the report can say when only the words changed: the unique index
  # takes `text_digest` as a fourth column. `NULL` in every row written before this
  # version, which `EhosContract.Deployment` reads as "not recorded".

  use Ecto.Migration

  @doc false
  @spec up() :: :ok
  def up do
    alter table(:eh_os_contract_deployments) do
      add :text_digest, :text
      add :text_digests, :map
    end

    drop index(:eh_os_contract_deployments, [], name: :eh_os_contract_deployments_versions_index)

    create unique_index(
             :eh_os_contract_deployments,
             [:contract, :contract_version, :wiring_version, :text_digest],
             name: :eh_os_contract_deployments_versions_index
           )

    :ok
  end

  # Rows that differ only in their words would break the index of three columns, so all
  # but the first of each are dropped first, while the index of four still serves the
  # join: the first says since when that version and wiring ran. What the later rows
  # recorded is not restored.
  @doc false
  @spec down() :: :ok
  def down do
    execute("""
    DELETE FROM eh_os_contract_deployments d
    USING eh_os_contract_deployments earlier
    WHERE d.contract = earlier.contract
      AND d.contract_version = earlier.contract_version
      AND d.wiring_version = earlier.wiring_version
      AND (earlier.first_seen_at, earlier.id) < (d.first_seen_at, d.id)
    """)

    drop index(:eh_os_contract_deployments, [], name: :eh_os_contract_deployments_versions_index)

    create unique_index(
             :eh_os_contract_deployments,
             [:contract, :contract_version, :wiring_version],
             name: :eh_os_contract_deployments_versions_index
           )

    alter table(:eh_os_contract_deployments) do
      remove :text_digest
      remove :text_digests
    end

    :ok
  end
end
