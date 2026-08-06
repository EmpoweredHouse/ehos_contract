defmodule Taxvision.Repo.Migrations.PeriodIsACalendarMonth do
  use Ecto.Migration

  @moduledoc """
  A period's date range cannot say anything but "this calendar month".

  `Taxvision.Periods.ensure!/1` already derives `starts_on`/`ends_on` from the
  `YYYY-MM` name — the first day of that month, and its last. There has never
  been an application code path that sets a different range: confirmed by
  reading every insert against this table, not assumed. So the risk this
  constraint closes is not a feature anyone uses, it is a row anyone could still
  write by hand — a raw `UPDATE`, a seed script, a future caller nobody has
  written yet — that a re-printed report would then disagree with itself about.

  Decided in conversation, 6 August: the accounting period's range never
  changes independently of its name, so append-only periods (PLAN.md's other
  option) are not needed. A `CHECK` is the whole fix, and it is one because the
  question it answers is "no" — a "yes" would have needed a table, not a
  constraint.
  """

  def change do
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
