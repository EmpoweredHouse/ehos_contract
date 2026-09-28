defmodule Taxvision.PeriodsTest do
  @moduledoc """
  What a period is, since E9c (plan, the decisions before E9c): its **name**,
  "2026-07", is the identifier the facts carry, held to a format by the domain's
  `:period`; its **row** holds its dates.

  Until then the row was the identifier: a name was resolved to a uuid once, at the
  request edge, so "2026-7" beside "2026-07" was impossible because no such row
  existed. It is impossible now because the value's invariant refuses the name — the
  flow test shows it at dispatch — and the timer on the first of the month can name
  the next period without asking the database. What went with the uuid: the
  measurements of the no-join rule's queries, which were the v1 handlers', and come
  back with E9c-2's tasks, if they are still worth measuring.
  """

  use Taxvision.DataCase, async: false

  @period "2026-07"

  describe "the name" do
    test "is a month, YYYY-MM, and nothing else" do
      assert Taxvision.Periods.name?("2026-07")
      refute Taxvision.Periods.name?("2026-7")
      refute Taxvision.Periods.name?("2026-13")
      refute Taxvision.Periods.name?("2026-07-01")
      refute Taxvision.Periods.name?(nil)
    end

    test "when the next check is due, and of which month, across a year" do
      alias Taxvision.Periods

      assert Periods.next_month_start(~U[2026-09-15 10:30:00Z]) == ~U[2026-10-01 00:00:00Z]
      assert Periods.next_month_start(~U[2026-12-31 23:59:59Z]) == ~U[2027-01-01 00:00:00Z]
      assert Periods.ended_before(~U[2027-01-01 00:00:00Z]) == "2026-12"
      assert Periods.ended_before(~U[2026-10-01 00:00:00Z]) == "2026-09"
    end

    test "a month has ended by the first of the next one, and not before" do
      assert Taxvision.Periods.ended_by?("2026-08", ~U[2026-09-01 00:00:00Z])
      refute Taxvision.Periods.ended_by?("2026-09", ~U[2026-09-30 23:59:59Z])
      refute Taxvision.Periods.ended_by?("2062-08", ~U[2026-09-15 10:00:00Z])
      assert Taxvision.Periods.ended_by?("2026-12", ~U[2027-01-01 00:00:00Z])
    end
  end

  describe "the row" do
    test "the date range is derived from the name once, in one place" do
      period = Taxvision.Periods.fetch!(@period)

      assert period.starts_on == ~D[2026-07-01]
      assert period.ends_on == ~D[2026-07-31]
    end

    test "creating the same period twice gives one row" do
      before = Taxvision.Periods.fetch!(@period)
      assert Taxvision.Periods.ensure!(@period) == before
    end
  end

  describe "the range cannot say anything but \"this calendar month\"" do
    # `ensure!/1` is the only application code path that writes this table, and it
    # always derives the range from the name — so these three constraints have no
    # legitimate caller to break. They exist for what `ensure!/1` cannot prevent: a
    # hand-written row, whether from a seed, a migration, or a caller not yet
    # written. `insert_all/2` is used deliberately, because it skips changesets and
    # reaches the database directly — the same reason `dispatch_test.exs` uses it
    # to prove a different constraint is enforced by Postgres, not by Elixir.
    defp bad_period(fields) do
      Repo.insert_all(
        Taxvision.Periods.Period,
        [
          Map.merge(
            %{
              id: Ecto.UUID.generate(),
              name: "2026-09",
              starts_on: ~D[2026-09-01],
              ends_on: ~D[2026-09-30]
            },
            fields
          )
        ]
      )
    end

    test "a name that is not YYYY-MM is refused" do
      assert_raise Postgrex.Error, ~r/name_is_year_month/, fn ->
        bad_period(%{name: "2026-9"})
      end
    end

    test "a start date that is not the first of the named month is refused" do
      # `ends_on` is moved along with `starts_on` so that only the constraint under
      # test fails — left at the September default, it would also violate
      # `ends_on_is_the_last_of_the_named_month` (it is defined relative to
      # `starts_on`, not to `name`), and Postgres reporting that one instead would
      # make this test pass for the wrong reason.
      assert_raise Postgrex.Error, ~r/starts_on_is_the_first_of_the_named_month/, fn ->
        bad_period(%{starts_on: ~D[2026-09-02], ends_on: ~D[2026-10-01]})
      end
    end

    test "an end date that is not the last of the named month is refused" do
      assert_raise Postgrex.Error, ~r/ends_on_is_the_last_of_the_named_month/, fn ->
        bad_period(%{ends_on: ~D[2026-09-29]})
      end
    end

    test "the range `ensure!/1` actually writes passes all three constraints" do
      # The control: a constraint that also rejects the good row would silently
      # break the one path that is supposed to keep working.
      assert %{starts_on: ~D[2026-09-01], ends_on: ~D[2026-09-30]} =
               Taxvision.Periods.ensure!("2026-09")
    end
  end
end
