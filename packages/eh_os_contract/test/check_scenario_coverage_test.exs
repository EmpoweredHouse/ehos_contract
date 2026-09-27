defmodule EhOsContract.CheckScenarioCoverageTest do
  @moduledoc """
  Plan EL2, rule 4 of the prose review: **a policy, a process manager or a query no scenario
  runs** (ESDM's `feature-without-scenarios`), a warning at its declaration, with
  one of each covered beside it.
  """

  use EhOsContract.DslCase, async: false

  alias EhOsContract.Check.{Completeness, Finding}

  @visits EhOsContract.Next.Fixtures.CoverageVisits

  setup_all do
    compile(
      contract("CoverageVisits", """
        aggregate :visit, "Wizyta" do
          identity :visit_id
          command :book, "Umów", by: :reception, emits: :booked
          command :remind, "Przypomnij", emits: :reminded
          event :booked, "Umówiono"
          event :reminded, "Przypomniano"
        end

        policy :remind_on_booking, "Przypomnij po umówieniu", handles: :booked, issues: :remind
        policy :remind_again, "Przypomnij jeszcze raz", handles: :reminded, issues: :remind

        process_manager :chase, "Pogoń" do
          correlate :visit_id
          starts_on :booked, sets: :later
          timer :later, wait: {1, :day}, issues: :remind
          ends_on :reminded
        end

        read_model :bookings, "Wizyty", projects: :booked do
          field :visit_id, :id
        end

        query :bookings_of, "Wizyty", reads: :bookings, by: :reception do
          param :visit_id, :id
        end

        query :all_bookings, "Wszystkie wizyty", reads: :bookings, by: :reception

        process :visit, "Wizyta" do
          correlate :visit_id
        end

        scenario "umówienie — przypomnienie" do
          on :booked
          scope :remind_on_booking
          issues :remind
        end

        scenario "zapytanie o wizytę" do
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
