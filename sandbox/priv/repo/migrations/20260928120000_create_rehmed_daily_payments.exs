defmodule EhOsContractHost.Repo.Migrations.CreateRehmedDailyPayments do
  @moduledoc "The table of `Rehmed.Settlement.DailyTotals`, `R-07`: one row per payment."

  use Ecto.Migration

  def change do
    create table(:rehmed_daily_payments, primary_key: false) do
      add :event_id, :uuid, primary_key: true
      add :business_date, :date, null: false
      add :method, :string, null: false
      add :amount, :bigint, null: false
    end

    create index(:rehmed_daily_payments, [:business_date])
  end
end
