defmodule Taxvision.Repo.Migrations.CreateEventLog do
  use Ecto.Migration

  def change do
    create table(:pns_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :type, :string, null: false
      add :contract, :string, null: false
      # Bez tej kolumny każdy deploy, który usuwa zdarzenie, produkuje fałszywe
      # alarmy w nakładce. Tanie teraz, niemożliwe do dopisania później.
      add :contract_version, :string, null: false
      add :correlation_id, :binary_id, null: false
      add :causation_id, :binary_id
      add :payload, :map, null: false, default: "{}"
      add :actor, :string
      add :occurred_at, :utc_datetime_usec, null: false
    end

    create index(:pns_events, [:type])
    create index(:pns_events, [:correlation_id])
    # Krawędź zaobserwowana to `causation_id` — po tym idzie zapytanie
    # odtwarzające faktyczny graf.
    create index(:pns_events, [:causation_id])
    create index(:pns_events, [:occurred_at])

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
  end
end
