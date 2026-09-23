defmodule EhOsContract.Migrations.V01 do
  @moduledoc false

  # The engine's storage as it stood on 2026-08-21, created in one step.
  #
  # **The final shape, not the history.** The tables reached this shape through
  # four migrations and one alter in the host application, and replaying those
  # increments here would make every new consumer pay for a week of our
  # indecision. `instance_id` and `process` are columns of `pns_events` from the
  # first `create`; that they were added a day later is a fact about this
  # repository, not about anybody's database.
  #
  # The comments below are the ones the original migrations carried. They are the
  # reason each column exists, and dropping them in a move would have been the
  # expensive half of the move.

  use Ecto.Migration

  @doc false
  @spec up() :: :ok
  def up do
    create table(:pns_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :type, :string, null: false
      add :contract, :string, null: false
      # Without this column, every deploy that removes an event produces false
      # alarms in the overlay. Cheap now, impossible to add later.
      add :contract_version, :string, null: false
      add :correlation_id, :binary_id, null: false
      add :causation_id, :binary_id
      add :payload, :map, null: false, default: "{}"
      add :actor, :string
      add :occurred_at, :utc_datetime_usec, null: false
      # Run identity, computed at emit time from the fields declared in
      # `instance:`. Computing it in a query from the payload would be possible,
      # but it would tie every query to **today's** contract version — and the log
      # spans every version since the first deploy. That is the same argument that
      # put `contract_version` here.
      add :process, :string
      add :instance_id, :string
    end

    create index(:pns_events, [:type])
    create index(:pns_events, [:correlation_id])
    # An observed edge is a `causation_id` — this is what the query
    # reconstructing the actual graph runs on.
    create index(:pns_events, [:causation_id])
    create index(:pns_events, [:occurred_at])
    # Every per-run query runs on this: the `trace` assertion, the instance
    # counter on an edge, the list of one run's events.
    create index(:pns_events, [:instance_id])
    create index(:pns_events, [:process, :instance_id])

    create table(:pns_event_handlings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :event_id, :binary_id, null: false
      add :handler, :string, null: false
      add :attempt, :integer, null: false, default: 1
      add :status, :string, null: false
      add :duration_us, :integer
      add :error, :text
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:pns_event_handlings, [:event_id])
    create index(:pns_event_handlings, [:handler, :status])

    # What was declared, and when it was in force.
    #
    # `contract_version` on an event answers which agreement was in force. It
    # cannot answer whether a **path** was declared at the time, because
    # `version/0` hashes the contract and paths come from handlers — so deleting a
    # handler changes the graph without changing any version stamped anywhere.
    #
    # One row per distinct wiring that has booted. Written at startup, so the
    # graph still comes from the binary that actually runs.
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

    # What a synchronous handler was doing when it died.
    #
    # A synchronous handler runs inside the emitting transaction, so when it
    # raises, the transaction takes the handling row and the event down with it.
    # That is correct — nothing happened, so the log must not claim it did — and it
    # leaves the most interesting failure invisible in the artifact that exists to
    # make failures visible (ADR §13).
    #
    # **Deliberately no foreign key to `pns_events`.** There is nothing to point
    # at: the event was rolled back and never existed. What survives a rollback is
    # the correlation id, generated before the transaction opened, so that is the
    # handle this table carries. A row here says "this command was attempted and
    # died", which is a different kind of statement from every other row in the
    # log — hence a different table rather than a status on `pns_event_handlings`.
    create table(:pns_handler_failures, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :contract, :string, null: false
      add :event_type, :string, null: false
      add :handler, :string, null: false
      add :correlation_id, :binary_id
      # Known even though the event was rolled back: it is computed from the
      # payload, not read from the log. It is what lets the path report say how
      # many runs are failing rather than only that something is.
      add :instance_id, :string
      add :error, :text, null: false
      add :occurred_at, :utc_datetime_usec, null: false
    end

    create index(:pns_handler_failures, [:handler])
    create index(:pns_handler_failures, [:occurred_at])

    # When a declared external dependency was seen to be unavailable.
    #
    # The fourth assertion verdict needs this and nothing else can supply it.
    # Without it a registry outage inside an assertion window counts as a
    # **violation** — the report tells a client they broke their own agreement when
    # somebody else's server was down, which is the most expensive kind of false
    # positive this product can produce.
    #
    # **Observations, not intervals.** An adapter learns that one call failed. It
    # never learns when the service came back, because nothing tells it — it would
    # have to keep asking, and a health-checker is a different product. So each row
    # is one moment, and "was it down during this window" is answered by whether
    # any moment falls inside it.
    #
    # No reference to a run. A registry being down is not something that happens to
    # one company's month; it happens to everybody at once, which is why the row is
    # keyed by dependency and time rather than by `instance_id`.
    create table(:pns_dependency_observations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :contract, :string, null: false
      # The name from the contract's `external` declaration, never a vendor's. An
      # observation about "KSeF" would tie the log to a supplier the contract is
      # written to outlive.
      add :external, :string, null: false
      add :reason, :text
      add :observed_at, :utc_datetime_usec, null: false
    end

    # The only query there is: this dependency, within this window.
    create index(:pns_dependency_observations, [:contract, :external, :observed_at])

    :ok
  end

  @doc false
  @spec down() :: :ok
  def down do
    drop table(:pns_dependency_observations)
    drop table(:pns_handler_failures)
    drop table(:pns_deployments)
    drop table(:pns_event_handlings)
    drop table(:pns_events)

    :ok
  end
end
