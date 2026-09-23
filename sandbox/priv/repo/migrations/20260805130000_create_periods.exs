defmodule Taxvision.Repo.Migrations.CreatePeriods do
  use Ecto.Migration

  @moduledoc """
  An accounting period stops being a string and becomes a row.

  The gain is not the obvious one — "one period exists" is also what a unique
  index on a text column buys. The real gain is **canonicalisation**: with one row
  per period, `"2026-7"` beside `"2026-07"` stops being possible rather than
  merely discouraged.

  The date range is what this table really exists for: two different modules need
  the same answer to "when does July end", and cross-module joins are forbidden.
  """

  def change do
    # Owned by: Taxvision.Periods
    create table(:taxvision_periods, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :starts_on, :date, null: false
      add :ends_on, :date, null: false
    end

    # Canonicalisation lives here, not in a naming convention.
    create unique_index(:taxvision_periods, [:name])

    # Two modules, the same answer, two copies. The duplication is **strategic and
    # has a named source of truth** (`Taxvision.Periods`) — it is neither a shared
    # table nor a join.
    alter table(:taxvision_tasks) do
      add :due_on, :date
    end

    alter table(:taxvision_accounting_months) do
      add :closes_on, :date
    end
  end
end
