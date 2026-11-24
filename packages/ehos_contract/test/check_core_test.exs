defmodule EhosContract.CheckCoreTest do
  @moduledoc """
  Plan DD, L2 (#272): **the core is where things are decided.** A command of a core
  context that rejects nothing is a notice (`core-command-never-refuses`), unless a
  reaction issues it; a unit of a core context none of whose commands can be refused
  is a warning (`core-unit-records-only`); and a unit's page says "Records only"
  wherever it is.
  """

  use EhosContract.DslCase, async: false

  alias EhosContract.Check.{Completeness, Finding}
  alias EhosContract.Pages

  @domain EhosContract.CheckCoreTest.Clinic
  @visits EhosContract.CheckCoreTest.Visits
  @reports EhosContract.CheckCoreTest.Reports

  setup_all do
    compile(
      """
      defmodule #{inspect(@domain)} do
        use EhosContract.Domain, name: :core_rules, language: :en

        subdomain :core, "Core", type: :core
        subdomain :generic, "Generic", type: :generic

        context :scheduling, "Scheduling", subdomain: :core
        context :reporting, "Reporting", subdomain: :generic

        actor :reception, :human, "Front desk"
      end

      defmodule #{inspect(@visits)} do
        use EhosContract.Contract, domain: #{inspect(@domain)}, context: :scheduling,
          id: "core_rules.visits"

        aggregate :visit, "Visit" do
          identity :visit_id
          invariant :once, "A visit ends once"

          command :book, "Book", by: :reception, emits: :booked
          command :close, "Close", by: :reception, emits: :closed, rejects: :once
          command :remind, "Remind", emits: :reminded
          command :chase, "Chase", emits: :chased
          command :confirm, "Confirm", by: :reception, emits: :confirmed

          event :booked, "Booked"
          event :closed, "Closed"
          event :reminded, "Reminded"
          event :chased, "Chased"
          event :confirmed, "Confirmed"
        end

        aggregate :draft, "Draft" do
          identity :draft_id
        end

        aggregate :arrival, "Arrival" do
          identity :arrival_id
          event :arrived, "Patient arrived", recorded_by: :reception
        end

        policy :remind_on_booking, "Remind after booking", handles: :booked, issues: :remind
        policy :confirm_on_booking, "Confirm after booking", handles: :booked, issues: :confirm

        process_manager :chasing, "Chase a visit" do
          correlate :visit_id
          starts_on :booked, sets: :chase_due
          timer :chase_due, "Chase due", wait: {1, :day}, issues: :chase
          ends_on :closed
        end

        scenario "a closed visit does not close a second time" do
          given :closed
          command :close
          rejected :once
        end
      end

      defmodule #{inspect(@reports)} do
        use EhosContract.Contract, domain: #{inspect(@domain)}, context: :reporting,
          id: "core_rules.reports"

        aggregate :report, "Report" do
          identity :report_id
          command :file, "File", by: :reception, emits: :filed
          event :filed, "Filed"
        end
      end
      """,
      "clinic.ex"
    )

    :ok
  end

  defp found(rule) do
    for %Finding{rule: ^rule} = f <- Completeness.findings([@visits, @reports]),
        do: {f.message, Finding.place(f)}
  end

  test "core-command-never-refuses: a core command rejecting nothing, and one a policy issues that a person may issue too; control: one that rejects, one only a policy issues, one only a timer issues, one outside the core" do
    assert [
             {"command :book of EhosContract.CheckCoreTest.Visits, in core context :scheduling, " <>
                "rejects nothing: no rule of its unit can refuse it", {"clinic.ex", 21}},
             {"command :confirm of" <> _, {"clinic.ex", 25}}
           ] = Enum.sort_by(found("core-command-never-refuses"), &elem(&1, 1))
  end

  test "core-unit-records-only: a core unit with recorded events only; control: a core unit that rejects, a core unit with no event, a generic unit that records only" do
    assert [
             {"aggregate :arrival of EhosContract.CheckCoreTest.Visits, in core context " <>
                ":scheduling, only records: no command it takes can be refused",
              {"clinic.ex", 38}}
           ] = found("core-unit-records-only")
  end

  test "a unit's page says it records only, wherever it is; control: a unit that decides" do
    pages = Pages.render(@domain, [@visits, @reports])
    marker = "Records only: no command it takes can be refused."

    page = fn suffix ->
      Enum.find_value(pages, fn {path, text} -> String.ends_with?(path, suffix) && text end)
    end

    assert page.("aggregates/arrival.md") =~ marker
    assert page.("aggregates/report.md") =~ marker
    refute page.("aggregates/visit.md") =~ marker
    refute page.("aggregates/draft.md") =~ marker
  end
end
