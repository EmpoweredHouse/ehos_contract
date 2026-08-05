defmodule Taxvision.Repo.Migrations.AddProcessInstance do
  use Ecto.Migration

  def change do
    alter table(:pns_events) do
      # Run identity, computed at emit time from the fields declared in
      # `instance:`. Computing it in a query from the payload would be possible,
      # but it would tie every query to **today's** contract version — and the log
      # spans every version since the first deploy. That is the same argument that
      # put `contract_version` here.
      add :process, :string
      add :instance_id, :string
    end

    # Every per-run query runs on this: the `trace` assertion, the instance
    # counter on an edge, the list of one run's events.
    create index(:pns_events, [:instance_id])
    create index(:pns_events, [:process, :instance_id])
  end
end
