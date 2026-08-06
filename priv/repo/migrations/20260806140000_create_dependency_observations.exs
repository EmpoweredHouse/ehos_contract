defmodule Taxvision.Repo.Migrations.CreateDependencyObservations do
  use Ecto.Migration

  @moduledoc """
  When a declared external dependency was seen to be unavailable.

  The fourth assertion verdict needs this and nothing else can supply it. Without it a
  registry outage inside an assertion window counts as a **violation** — the report tells
  a client they broke their own agreement when somebody else's server was down, which is
  the most expensive kind of false positive this product can produce.

  **Observations, not intervals.** An adapter learns that one call failed. It never learns
  when the service came back, because nothing tells it — it would have to keep asking, and
  a health-checker is a different product. So each row is one moment, and "was it down
  during this window" is answered by whether any moment falls inside it.

  No reference to a run. A registry being down is not something that happens to one
  company's month; it happens to everybody at once, which is why the row is keyed by
  dependency and time rather than by `instance_id`.
  """

  def change do
    create table(:pns_dependency_observations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :contract, :string, null: false
      # The name from the contract's `external` declaration, never a vendor's. An
      # observation about "KSeF" would tie the log to a supplier the contract is written
      # to outlive.
      add :external, :string, null: false
      add :reason, :text
      add :observed_at, :utc_datetime_usec, null: false
    end

    # The only query there is: this dependency, within this window.
    create index(:pns_dependency_observations, [:contract, :external, :observed_at])
  end
end
