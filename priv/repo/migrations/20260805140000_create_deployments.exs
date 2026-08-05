defmodule Taxvision.Repo.Migrations.CreateDeployments do
  use Ecto.Migration

  @moduledoc """
  What was declared, and when it was in force.

  `contract_version` on an event answers which agreement was in force. It cannot
  answer whether a **path** was declared at the time, because `version/0` hashes
  the contract and paths come from handlers — so deleting a handler changes the
  graph without changing any version stamped anywhere.

  One row per distinct wiring that has booted. Written at startup, so the graph
  still comes from the binary that actually runs.
  """

  def change do
    create table(:pns_deployments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :contract, :string, null: false
      add :contract_version, :string, null: false
      # Hash of the declared edges. Separate from `contract_version` on purpose:
      # a handler change alters what the code does without altering what the
      # client agreed to, and conflating the two would either hide wiring
      # changes or bump the agreement for a refactor.
      add :wiring_version, :string, null: false
      add :events, {:array, :string}, null: false
      add :edges, {:array, :string}, null: false
      add :first_seen_at, :utc_datetime_usec, null: false
    end

    create unique_index(:pns_deployments, [:contract, :contract_version, :wiring_version])
    create index(:pns_deployments, [:first_seen_at])
  end
end
