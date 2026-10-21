defmodule EhOsContract.CheckScenarioCoverageTest do
  @moduledoc """
  Plan EL2, rule 4 of the prose review: **a policy, a process manager or a query no scenario
  runs** (ESDM's `feature-without-scenarios`), a warning at its declaration, with
  one of each covered beside it.
  """

  use EhOsContract.DslCase, async: false

  alias EhOsContract.Check.{Completeness, Finding}

  @visits EhOsContract.Fixtures.CoverageVisits

  setup_all do
    compile(
      contract("CoverageVisits", """
        aggregate :visit, "Visit" do
          identity :visit_id
          command :book, "Book", by: :reception, emits: :booked
          command :remind, "Remind", emits: :reminded
          event :booked, "Booked"
          event :reminded, "Reminded"
        end

        policy :remind_on_booking, "Remind after booking", handles: :booked, issues: :remind
        policy :remind_again, "Remind again", handles: :reminded, issues: :remind

        process_manager :chase, "Chase" do
          correlate :visit_id
          starts_on :booked, sets: :later
          timer :later, "Later", wait: {1, :day}, issues: :remind
          ends_on :reminded
        end

        read_model :bookings, "Visits", projects: :booked do
          field :visit_id, :id
        end

        query :bookings_of, "Visits", reads: :bookings, by: :reception do
          param :visit_id, :id
        end

        query :all_bookings, "All visits", reads: :bookings, by: :reception

        scenario "booking — reminder" do
          on :booked
          target :remind_on_booking
          issues :remind
        end

        scenario "asking about a visit" do
          given :booked
          query :bookings_of, %{visit_id: "visit-anna"}
          answers []
        end
      """),
      "coverage_visits.ex"
    )

    :ok
  end

  test "an uncovered policy, process manager and query, each at its declaration" do
    found =
      for %Finding{rule: "reaction-without-scenario"} = f <- Completeness.findings([@visits]),
          do: {f.message, Finding.place(f)}

    assert [
             {"policy :remind_again of " <> _, {"coverage_visits.ex", 13}},
             {"process manager :chase of " <> _, {"coverage_visits.ex", 15}},
             {"query :all_bookings of " <> _, {"coverage_visits.ex", 30}}
           ] = Enum.sort_by(found, &elem(&1, 1))
  end
end
