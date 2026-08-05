defmodule Taxvision.Repo.Migrations.CreateHandlerFailures do
  use Ecto.Migration

  @moduledoc """
  What a synchronous handler was doing when it died.

  A synchronous handler runs inside the emitting transaction, so when it raises,
  the transaction takes the handling row and the event down with it. That is
  correct — nothing happened, so the log must not claim it did — and it leaves the
  most interesting failure invisible in the artifact that exists to make failures
  visible (ADR §13).

  **Deliberately no foreign key to `pns_events`.** There is nothing to point at: the
  event was rolled back and never existed. What survives a rollback is the
  correlation id, generated before the transaction opened, so that is the handle
  this table carries. A row here says "this command was attempted and died", which
  is a different kind of statement from every other row in the log — hence a
  different table rather than a status on `pns_event_handlings`.
  """

  def change do
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
  end
end
