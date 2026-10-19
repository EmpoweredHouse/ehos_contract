defmodule EhOsContract.ReactionRulesTest do
  @moduledoc """
  Plan EP2: **a reaction's rules, and the scenario that illustrates them.** A policy, an
  effect and a process manager name their rules as `constraint`s, a process manager
  its `invariant`s too, as a command and a query do; a scenario names in
  `illustrates:` the rules of its target it shows (S10), and `check` warns of a rule
  no scenario shows (`prose-without-scenario`). An effect's constraint is prose alone:
  no scenario runs an effect, so `check` says nothing of it.
  """

  use EhOsContract.DslCase, async: false

  alias EhOsContract.Check.{Completeness, Finding}
  alias EhOsContract.{Model, Pages, View}

  @visits """
    aggregate :visit, "Visit" do
      identity :visit_id
      command :close, "Close", by: :reception, emits: :closed
      command :report, "Report", emits: :reported
      command :waive, "Skip", emits: :waived
      event :closed, "Closed" do
        field :reportable, :boolean
      end
      event :reported, "Reported"
      event :waived, "Skipped"
    end

    policy :report_on_close, "Closing — a report or a skip",
      handles: :closed, issues: [:report, :waive] do
      constraint :only_reportable, "We report only the services that must be reported", source: "Q-21"
      constraint :one_answer, "Every closing gets exactly one answer"
    end

    policy :remind_on_waive, "Skipping — reminder", handles: :waived, issues: :report do
      constraint :quiet_hours, "No reminders at night"
    end

    effect :send_report, "Send the report", handles: :reported, idempotency: [key: :event_id, owner: :self] do
      constraint :within_limits, "The adapter keeps within the rate limits and retries", source: "07 §2.3"
    end

    process_manager :chase, "Chase" do
      correlate :visit_id
      starts_on :closed, sets: :due
      timer :due, "Due", wait: {1, :day}, issues: :report
      ends_on :reported
      invariant :one_timer, "A visit has at most one reminder at a time"
      constraint :business_days, "A reminder comes on a business day"
    end

    read_model :visits, "Visits", projects: :closed do
      field :visit_id, :id
    end

    query :visits_of, "Visits", reads: :visits, by: :reception do
      param :visit_id, :id
      constraint :own_clinic, "Reception sees only its own clinic's visits"
    end

    scenario "physiotherapy — report", illustrates: :only_reportable do
      on :closed, %{reportable: true}
      target :report_on_close
      issues :report
    end

    scenario "closing — a reminder in a day",
      illustrates: [:one_timer, :business_days] do
      on :closed, %{reportable: true}
      target :chase
      sets :due
    end

    scenario "reminder — report", illustrates: :one_timer do
      on :due
      issues :report
    end

    scenario "reception's visits" do
      query :visits_of, %{visit_id: "visit-anna"}
      answers []
    end
  """

  # The line of the contract's file where `text` is, the body starting at line 4.
  defp line_of(text) do
    @visits |> String.split("\n") |> Enum.find_index(&String.contains?(&1, text)) |> Kernel.+(4)
  end

  setup_all do
    compile(
      """
      defmodule EhOsContract.ReactionRulesTest.Domain do
        use EhOsContract.Domain, name: :clinic, language: :pl
        subdomain :billing, "Settlement", type: :supporting
        context :settlement, "Settlement", subdomain: :billing
      end
      """,
      "reaction_rules_domain.ex"
    )

    %{
      model: compile_contract("ReactionRules", @visits),
      domain: Model.fetch(EhOsContract.ReactionRulesTest.Domain)
    }
  end

  describe "the model" do
    test "keeps each reaction's rules, and each scenario what it illustrates", %{model: model} do
      policy = Enum.find(model.policies, &(&1.name == :report_on_close))
      [effect] = model.effects
      [pm] = model.process_managers

      assert [
               %{name: :only_reportable, source: "Q-21"},
               %{name: :one_answer, source: nil}
             ] = policy.constraints

      assert [
               %{
                 name: :within_limits,
                 label: "The adapter keeps within the rate limits and retries"
               }
             ] =
               effect.constraints

      assert [%{name: :one_timer}] = pm.invariants
      assert [%{name: :business_days}] = pm.constraints

      assert %{illustrates: [:only_reportable]} =
               Enum.find(model.scenarios, &(&1.description == "physiotherapy — report"))
    end

    test "leaves the keys out where nothing is declared, so no digest moves" do
      model =
        compile_contract("ReactionRulesNone", """
          aggregate :visit, "Visit" do
            identity :visit_id
            command :close, "Close", by: :reception, emits: :closed
            command :report, "Report", emits: :reported
            event :closed, "Closed"
            event :reported, "Reported"
          end

          policy :report_on_close, "Closing", handles: :closed, issues: :report
          effect :send_report, "Send", handles: :reported, idempotency: [key: :event_id, owner: :self]

          process_manager :chase, "Chase" do
            correlate :visit_id
            starts_on :closed
            ends_on :reported
          end

          scenario "closing — report" do
            on :closed
            target :report_on_close
            issues :report
          end
        """)

      [policy] = model.policies
      [effect] = model.effects
      [pm] = model.process_managers
      [scenario] = model.scenarios

      refute Map.has_key?(policy, :constraints)
      refute Map.has_key?(effect, :constraints)
      refute Map.has_key?(pm, :constraints)
      refute Map.has_key?(pm, :invariants)
      refute Map.has_key?(scenario, :illustrates)
    end
  end

  describe "S10" do
    test "refuses a rule the scenario's target does not have" do
      message =
        refuse_contract("IllustratesUnknown", """
          aggregate :visit, "Visit" do
            identity :visit_id
            command :close, "Close", by: :reception, emits: :closed
            command :report, "Report", emits: :reported
            event :closed, "Closed"
            event :reported, "Reported"
          end

          policy :report_on_close, "Closing", handles: :closed, issues: :report do
            constraint :only_reportable, "Reportable services only"
          end

          scenario "closing — report", illustrates: :one_answer do
            on :closed
            issues :report
          end
        """)

      assert message =~
               ~s|S10: scenario "closing — report" illustrates :one_answer, which is no | <>
                 "rule of policy :report_on_close: it illustrates the policy's constraints by name"
    end

    test "sends a command's scenario to `rejected`" do
      message =
        refuse_contract("IllustratesCommand", """
          aggregate :visit, "Visit" do
            identity :visit_id
            invariant :paid, "Paid"
            command :close, "Close", by: :reception, emits: :closed, rejects: :paid
            event :closed, "Closed"
          end

          scenario "closing without payment", illustrates: :paid do
            command :close
            rejected :paid
          end
        """)

      assert message =~
               ~s|S10: scenario "closing without payment" names rules in illustrates:, but a | <>
                 "command's scenario shows the rules it is refused on with " <>
                 "`rejected`"
    end

    test "refuses a rule a query does not have, and a rule named twice" do
      message =
        refuse_contract("IllustratesQuery", """
          aggregate :visit, "Visit" do
            identity :visit_id
            command :close, "Close", by: :reception, emits: :closed
            event :closed, "Closed"
          end

          read_model :visits, "Visits", projects: :closed do
            field :visit_id, :id
          end

          query :visits_of, "Visits", reads: :visits, by: :reception do
            param :visit_id, :id
            constraint :own_clinic, "Own clinic only"
          end

          scenario "visits", illustrates: [:own_clinic, :own_clinic, :all_clinics] do
            query :visits_of, %{visit_id: "visit-anna"}
            answers []
          end
        """)

      assert message =~
               ~s|S10: scenario "visits" illustrates :all_clinics, which is no rule of query | <>
                 ":visits_of: it illustrates the query's constraints by name"

      assert message =~ ~s|S10: scenario "visits" illustrates :own_clinic twice|
    end
  end

  test "N1 refuses a process manager's constraint and invariant of one name" do
    message =
      refuse_contract("RulesTwice", """
        aggregate :visit, "Visit" do
          identity :visit_id
          command :close, "Close", by: :reception, emits: :closed
          event :closed, "Closed"
        end

        process_manager :chase, "Chase" do
          correlate :visit_id
          starts_on :closed
          ends_on :closed
          invariant :one_timer, "One reminder"
          constraint :one_timer, "One reminder"
        end
      """)

    assert message =~ "N1: process manager :chase has two rules named :one_timer"
  end

  test "check warns of each rule no scenario illustrates, at the rule, and not of an effect's" do
    findings = Completeness.findings([EhOsContract.Fixtures.ReactionRules])

    found =
      for %Finding{rule: "prose-without-scenario"} = f <- findings,
          do: {f.message, Finding.place(f)}

    one_answer = line_of("constraint :one_answer")
    own_clinic = line_of("constraint :own_clinic")

    assert [
             {"constraint :one_answer of policy :report_on_close of " <> _,
              {"reaction_rules.ex", ^one_answer}},
             {"constraint :own_clinic of query :visits_of of " <> _,
              {"reaction_rules.ex", ^own_clinic}}
           ] = Enum.sort_by(found, &elem(&1, 1))

    # A policy no scenario runs is reported once, by `reaction-without-scenario`, not
    # once more for its constraint (the EP2 review).
    assert [{"policy :remind_on_waive of " <> _, _}] =
             for(
               %Finding{rule: "reaction-without-scenario"} = f <- findings,
               do: {f.message, Finding.place(f)}
             )
  end

  test "view --details lists each reaction's rules", %{model: model, domain: domain} do
    tree = View.render(domain, [%{model | domain: domain.module}], details: true)

    assert tree =~
             "constraint only_reportable — We report only the services that must be reported"

    assert tree =~
             "constraint within_limits — The adapter keeps within the rate limits and retries"

    assert tree =~ "invariant one_timer — A visit has at most one reminder at a time"
  end

  test "the pages list each reaction's rules, and what a scenario illustrates", %{
    model: model,
    domain: domain
  } do
    pages = Pages.render(domain, [%{model | domain: domain.module}])
    dir = "settlement/reaction_rules"

    policy = pages["#{dir}/policies/report_on_close.md"]
    assert policy =~ "## Constraints\n\n- `only_reportable` — We report only the services"
    assert policy =~ "issues `report` — illustrates `only_reportable`"

    assert pages["#{dir}/effects/send_report.md"] =~
             "- `within_limits` — The adapter keeps within the rate limits and retries"

    pm = pages["#{dir}/process_managers/chase.md"]
    assert pm =~ "## Invariants\n\n- `one_timer` — A visit has at most one reminder at a time"
    assert pm =~ "## Constraints\n\n- `business_days`"
  end
end
