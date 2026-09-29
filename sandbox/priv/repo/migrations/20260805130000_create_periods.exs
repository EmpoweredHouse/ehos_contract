defmodule Taxvision.Repo.Migrations.CreatePeriods do
  use Ecto.Migration

  @moduledoc """
  An accounting period is a row, and its date range cannot say anything but "this
  calendar month".

  The gain is not the obvious one — "one period exists" is also what a unique index
  on a text column buys. The real gain is **canonicalisation**: with one row per
  period, `"2026-7"` beside `"2026-07"` stops being possible rather than merely
  discouraged. The date range is what the table exists for: `Taxvision.Periods` is
  the named source of truth for when a month starts and ends.

  **The checks, rather than trust in the one writer.** `Taxvision.Periods.ensure!/1`
  derives `starts_on`/`ends_on` from the `YYYY-MM` name and no code path sets a
  different range; a row written by hand — a raw `UPDATE`, a seed script, a caller
  nobody has written yet — would make a re-printed report disagree with itself. The
  range never changes independently of its name (decided 6 August), so a `CHECK` is
  the whole fix.

  Until the cut (plan stage E11c) this took four migrations, and three module tables
  of TaxVision's v1 referred to a period by foreign key. Since E9c the month is a
  contract's aggregate and nothing reads those tables, so they are not created.
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

    create constraint(:taxvision_periods, :name_is_year_month,
             check: "name ~ '^[0-9]{4}-[0-9]{2}$'"
           )

    create constraint(:taxvision_periods, :starts_on_is_the_first_of_the_named_month,
             check: "starts_on = to_date(name || '-01', 'YYYY-MM-DD')"
           )

    create constraint(:taxvision_periods, :ends_on_is_the_last_of_the_named_month,
             check: "ends_on = ((starts_on + interval '1 month') - interval '1 day')::date"
           )
  end
end
