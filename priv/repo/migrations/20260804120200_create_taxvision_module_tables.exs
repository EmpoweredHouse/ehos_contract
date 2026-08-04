defmodule Taxvision.Repo.Migrations.CreateTaxvisionModuleTables do
  use Ecto.Migration

  @moduledoc """
  Jedna baza, ale **tabele są prywatne dla modułu**. Nie ma wspólnego schematu,
  nie ma joinów międzymodułowych i nie ma widoków nad tabelami innego modułu.

  Prefiks nazwy jest tu dokumentacją własności, nie ozdobą: gdy ktoś napisze
  join z `taxvision_tasks` do `taxvision_notifications`, ma to wyglądać źle już
  w SQL-u, a nie tylko w raporcie z `boundary`.
  """

  def change do
    # Własność: Taxvision.Tasks
    create table(:taxvision_tasks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :company_id, :string, null: false
      add :period, :string, null: false
      add :name, :string, null: false
      add :status, :string, null: false, default: "open"
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:taxvision_tasks, [:company_id, :period])

    # Własność: Taxvision.AccountingMonth
    create table(:taxvision_accounting_months, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :company_id, :string, null: false
      add :period, :string, null: false
      add :status, :string, null: false
      add :opened_at, :utc_datetime_usec
    end

    create unique_index(:taxvision_accounting_months, [:company_id, :period])

    # Własność: Taxvision.Notifications
    create table(:taxvision_notifications, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :company_id, :string, null: false
      add :period, :string, null: false
      add :recipient, :string, null: false
      add :subject, :string, null: false
      add :body_ref, :string
      add :idempotency_key, :string, null: false
      add :sent_at, :utc_datetime_usec, null: false
    end

    create index(:taxvision_notifications, [:idempotency_key])
  end
end
