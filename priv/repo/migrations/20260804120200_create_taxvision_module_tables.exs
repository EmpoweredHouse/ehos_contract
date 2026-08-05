defmodule Taxvision.Repo.Migrations.CreateTaxvisionModuleTables do
  use Ecto.Migration

  @moduledoc """
  One database, but **the tables are private to their module**. There is no shared
  schema, no cross-module joins and no views over another module's tables.

  The name prefix documents ownership rather than decorating: when somebody writes
  a join from `taxvision_tasks` to `taxvision_notifications`, it is meant to look
  wrong in the SQL already, not only in a `boundary` report.
  """

  def change do
    # Owned by: Taxvision.Tasks
    create table(:taxvision_tasks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :company_id, :string, null: false
      add :period, :string, null: false
      add :name, :string, null: false
      add :status, :string, null: false, default: "open"
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:taxvision_tasks, [:company_id, :period])

    # Owned by: Taxvision.AccountingMonth
    create table(:taxvision_accounting_months, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :company_id, :string, null: false
      add :period, :string, null: false
      add :status, :string, null: false
      add :opened_at, :utc_datetime_usec
    end

    create unique_index(:taxvision_accounting_months, [:company_id, :period])

    # Owned by: Taxvision.Notifications
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
