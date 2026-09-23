defmodule Taxvision.Repo.Migrations.PeriodByIdentifier do
  use Ecto.Migration

  @moduledoc """
  Module tables refer to a period by identifier, not by name.

  Canonicalising periods into a table (5 August) made `"2026-7"` beside `"2026-07"`
  discouraged. A foreign key makes it impossible, which is the difference between a
  convention and a constraint — and it is the whole reason that table exists.

  The column is replaced rather than added beside the old one. Two representations of one
  thing is the drift this product detects for a living, and a `period` string next to a
  `period_id` would be exactly that, in our own schema.

  **Backfilled rather than assumed empty**, which the first version of this migration got
  wrong: it added the column `null: false` and passed against an empty test database while
  failing against a development one that had rows. The old string *is* the period's name,
  so the join that recovers the identifier exists — and writing it out is also the
  rehearsal for the client whose tables are not empty.

  Nothing is deleted. A row whose period name has no canonical row cannot be migrated, and
  the `NOT NULL` at the end is what refuses the migration in that case. A migration that
  quietly dropped business rows to make itself succeed would be worse than one that stops.

  **A foreign key, deliberately, even though it crosses a module boundary.** `boundary`
  stops a module from *reading* another's table; a reference constraint is the database
  refusing to hold a fact that points at nothing. Different jobs — the first is about who
  may write code against what, the second about what may be true at rest.
  """

  @tables [:taxvision_accounting_months, :taxvision_tasks, :taxvision_notifications]

  def up do
    for table <- @tables do
      alter table(table) do
        add :period_id, references(:taxvision_periods, type: :binary_id, on_delete: :restrict)
      end
    end

    flush()

    for table <- @tables do
      execute """
      UPDATE #{table} AS t
         SET period_id = p.id
        FROM taxvision_periods AS p
       WHERE p.name = t.period
      """
    end

    for table <- @tables do
      alter table(table) do
        modify :period_id, :binary_id, null: false
        remove :period
      end

      create index(table, [:period_id])
    end
  end

  def down do
    for table <- @tables do
      alter table(table) do
        add :period, :string
      end
    end

    flush()

    for table <- @tables do
      execute """
      UPDATE #{table} AS t
         SET period = p.name
        FROM taxvision_periods AS p
       WHERE p.id = t.period_id
      """
    end

    for table <- @tables do
      alter table(table) do
        modify :period, :string, null: false
        remove :period_id
      end
    end
  end
end
