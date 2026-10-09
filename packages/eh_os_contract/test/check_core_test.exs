defmodule EhOsContract.CheckCoreTest do
  @moduledoc """
  Plan DD, L2 (#272): **the core is where things are decided.** A command of a core
  context that rejects nothing is a notice (`core-command-never-refuses`), unless a
  reaction issues it; a unit of a core context none of whose commands can be refused
  is a warning (`core-unit-records-only`); and a unit's page says "Records only"
  wherever it is.
  """

  use EhOsContract.DslCase, async: false

  alias EhOsContract.Check.{Completeness, Finding}
  alias EhOsContract.Pages

  @domain EhOsContract.CheckCoreTest.Clinic
  @visits EhOsContract.CheckCoreTest.Visits
  @reports EhOsContract.CheckCoreTest.Reports

  setup_all do
    compile(
      """
      defmodule #{inspect(@domain)} do
        use EhOsContract.Domain, name: :core_rules, language: :pl

        subdomain :core, "Rdzeń", type: :core
        subdomain :generic, "Ogólne", type: :generic

        context :scheduling, "Umawianie", subdomain: :core
        context :reporting, "Sprawozdawczość", subdomain: :generic

        actor :reception, :human, "Recepcja"
      end

      defmodule #{inspect(@visits)} do
        use EhOsContract.Contract, domain: #{inspect(@domain)}, context: :scheduling,
          id: "core_rules.visits"

        aggregate :visit, "Wizyta" do
          identity :visit_id
          invariant :once, "Wizyta kończy się raz"

          command :book, "Umów", by: :reception, emits: :booked
          command :close, "Zamknij", by: :reception, emits: :closed, rejects: :once
          command :remind, "Przypomnij", emits: :reminded

          event :booked, "Umówiona"
          event :closed, "Zamknięta"
          event :reminded, "Przypomniano"
        end

        aggregate :arrival, "Przyjście" do
          identity :arrival_id
          event :arrived, "Pacjent przyszedł", recorded_by: :reception
        end

        policy :remind_on_booking, "Przypomnij po umówieniu", handles: :booked, issues: :remind

        scenario "zamknięta wizyta nie zamyka się drugi raz" do
          given :closed
          command :close
          rejected :once
        end
      end

      defmodule #{inspect(@reports)} do
        use EhOsContract.Contract, domain: #{inspect(@domain)}, context: :reporting,
          id: "core_rules.reports"

        aggregate :report, "Raport" do
          identity :report_id
          command :file, "Złóż", by: :reception, emits: :filed
          event :filed, "Złożony"
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

  test "core-command-never-refuses: a core command rejecting nothing; control: one that rejects, one a policy issues, one outside the core" do
    assert [
             {"command :book of EhOsContract.CheckCoreTest.Visits, in core context :scheduling, " <>
                "rejects nothing, so it is always accepted", {"clinic.ex", 21}}
           ] = found("core-command-never-refuses")
  end

  test "core-unit-records-only: a core unit with recorded events only; control: a core unit that rejects, a generic unit that records only" do
    assert [
             {"aggregate :arrival of EhOsContract.CheckCoreTest.Visits, in core context " <>
                ":scheduling, only records: no command it takes can be refused",
              {"clinic.ex", 30}}
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
  end
end
