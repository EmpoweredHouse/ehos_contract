defmodule EhOsContractHost.Repo.Migrations.CreateGraphLabDailyPayments do
  @moduledoc """
  The table of `GraphLab.Settlement.DailyTotals`, the test set's day of payments: one row
  per payment. On the branch `graph/explorer-plan` only, with the set.
  """

  use Ecto.Migration

  def change do
    create table(:graph_lab_daily_payments, primary_key: false) do
      add :event_id, :uuid, primary_key: true
      add :business_date, :date, null: false
      add :method, :string, null: false
      add :amount, :bigint, null: false
    end

    create index(:graph_lab_daily_payments, [:business_date])
  end
end
