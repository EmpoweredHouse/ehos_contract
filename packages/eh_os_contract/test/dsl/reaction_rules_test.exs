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
    aggregate :visit, "Wizyta" do
      identity :visit_id
      command :close, "Zamknij", by: :reception, emits: :closed
      command :report, "Zgłoś", emits: :reported
      command :waive, "Pomiń", emits: :waived
      event :closed, "Zamknięto" do
        field :reportable, :boolean
      end
      event :reported, "Zgłoszono"
      event :waived, "Pominięto"
    end

    policy :report_on_close, "Zamknięcie — zgłoszenie albo pominięcie",
      handles: :closed, issues: [:report, :waive] do
      constraint :only_reportable, "Zgłaszamy tylko usługi podlegające zgłoszeniu", source: "P-07"
      constraint :one_answer, "Każde zamknięcie dostaje dokładnie jedną odpowiedź"
    end

    policy :remind_on_waive, "Pominięcie — przypomnienie", handles: :waived, issues: :report do
      constraint :quiet_hours, "Nie przypominamy w nocy"
    end

    effect :send_report, "Wyślij zgłoszenie", handles: :reported, idempotency: [key: :event_id, owner: :self] do
      constraint :within_limits, "Adapter pilnuje limitów zapytań i ponawia je", source: "03 §4.2"
    end

    process_manager :chase, "Pogoń" do
      correlate :visit_id
      starts_on :closed, sets: :due
      timer :due, wait: {1, :day}, issues: :report
      ends_on :reported
      invariant :one_timer, "Wizyta ma najwyżej jedno przypomnienie naraz"
      constraint :business_days, "Przypomnienie przychodzi w dzień roboczy"
    end

    read_model :visits, "Wizyty", projects: :closed do
      field :visit_id, :id
    end

    query :visits_of, "Wizyty", reads: :visits, by: :reception do
      param :visit_id, :id
      constraint :own_clinic, "Recepcja widzi tylko wizyty swojej przychodni"
    end

    process :visit, "Wizyta" do
      correlate :visit_id
    end

    scenario "fizjoterapia — zgłoszenie", illustrates: :only_reportable do
      on :closed, %{reportable: true}
      target :report_on_close
      issues :report
    end

    scenario "zamknięcie — przypomnienie za dzień",
      illustrates: [:one_timer, :business_days] do
      on :closed, %{reportable: true}
      target :chase
      sets :due
    end

    scenario "przypomnienie — zgłoszenie", illustrates: :one_timer do
      on :due
      issues :report
    end

    scenario "wizyty recepcji" do
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
        subdomain :billing, "Rozliczenia", type: :supporting
        context :settlement, "Rozliczenia", subdomain: :billing
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
               %{name: :only_reportable, source: "P-07"},
               %{name: :one_answer, source: nil}
             ] = policy.constraints

      assert [%{name: :within_limits, label: "Adapter pilnuje limitów zapytań i ponawia je"}] =
               effect.constraints

      assert [%{name: :one_timer}] = pm.invariants
      assert [%{name: :business_days}] = pm.constraints

      assert %{illustrates: [:only_reportable]} =
               Enum.find(model.scenarios, &(&1.description == "fizjoterapia — zgłoszenie"))
    end

    test "leaves the keys out where nothing is declared, so no digest moves" do
      model =
        compile_contract("ReactionRulesNone", """
          aggregate :visit, "Wizyta" do
            identity :visit_id
            command :close, "Zamknij", by: :reception, emits: :closed
            command :report, "Zgłoś", emits: :reported
            event :closed, "Zamknięto"
            event :reported, "Zgłoszono"
          end

          policy :report_on_close, "Zamknięcie", handles: :closed, issues: :report
          effect :send_report, "Wyślij", handles: :reported, idempotency: [key: :event_id, owner: :self]

          process_manager :chase, "Pogoń" do
            correlate :visit_id
            starts_on :closed
            ends_on :reported
          end

          process :visit, "Wizyta" do
            correlate :visit_id
          end

          scenario "zamknięcie — zgłoszenie" do
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
          aggregate :visit, "Wizyta" do
            identity :visit_id
            command :close, "Zamknij", by: :reception, emits: :closed
            command :report, "Zgłoś", emits: :reported
            event :closed, "Zamknięto"
            event :reported, "Zgłoszono"
          end

          policy :report_on_close, "Zamknięcie", handles: :closed, issues: :report do
            constraint :only_reportable, "Tylko usługi podlegające zgłoszeniu"
          end

          process :visit, "Wizyta" do
            correlate :visit_id
          end

          scenario "zamknięcie — zgłoszenie", illustrates: :one_answer do
            on :closed
            issues :report
          end
        """)

      assert message =~
               ~s|S10: scenario "zamknięcie — zgłoszenie" illustrates :one_answer, which is no | <>
                 "rule of policy :report_on_close: it illustrates the policy's constraints by name"
    end

    test "sends a command's scenario to `rejected`" do
      message =
        refuse_contract("IllustratesCommand", """
          aggregate :visit, "Wizyta" do
            identity :visit_id
            invariant :paid, "Zapłacono"
            command :close, "Zamknij", by: :reception, emits: :closed, rejects: :paid
            event :closed, "Zamknięto"
          end

          process :visit, "Wizyta" do
            correlate :visit_id
          end

          scenario "zamknięcie bez zapłaty", illustrates: :paid do
            command :close
            rejected :paid
          end
        """)

      assert message =~
               ~s|S10: scenario "zamknięcie bez zapłaty" names rules in illustrates:, but a | <>
                 "command's scenario shows the rules it is refused on with " <>
                 "`rejected`"
    end

    test "refuses a rule a query does not have, and a rule named twice" do
      message =
        refuse_contract("IllustratesQuery", """
          aggregate :visit, "Wizyta" do
            identity :visit_id
            command :close, "Zamknij", by: :reception, emits: :closed
            event :closed, "Zamknięto"
          end

          read_model :visits, "Wizyty", projects: :closed do
            field :visit_id, :id
          end

          query :visits_of, "Wizyty", reads: :visits, by: :reception do
            param :visit_id, :id
            constraint :own_clinic, "Tylko swoja przychodnia"
          end

          process :visit, "Wizyta" do
            correlate :visit_id
          end

          scenario "wizyty", illustrates: [:own_clinic, :own_clinic, :all_clinics] do
            query :visits_of, %{visit_id: "visit-anna"}
            answers []
          end
        """)

      assert message =~
               ~s|S10: scenario "wizyty" illustrates :all_clinics, which is no rule of query | <>
                 ":visits_of: it illustrates the query's constraints by name"

      assert message =~ ~s|S10: scenario "wizyty" illustrates :own_clinic twice|
    end
  end

  test "N1 refuses a process manager's constraint and invariant of one name" do
    message =
      refuse_contract("RulesTwice", """
        aggregate :visit, "Wizyta" do
          identity :visit_id
          command :close, "Zamknij", by: :reception, emits: :closed
          event :closed, "Zamknięto"
        end

        process_manager :chase, "Pogoń" do
          correlate :visit_id
          starts_on :closed
          ends_on :closed
          invariant :one_timer, "Jedno przypomnienie"
          constraint :one_timer, "Jedno przypomnienie"
        end

        process :visit, "Wizyta" do
          correlate :visit_id
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

    assert tree =~ "constraint only_reportable — Zgłaszamy tylko usługi podlegające zgłoszeniu"
    assert tree =~ "constraint within_limits — Adapter pilnuje limitów zapytań i ponawia je"
    assert tree =~ "invariant one_timer — Wizyta ma najwyżej jedno przypomnienie naraz"
  end

  test "the pages list each reaction's rules, and what a scenario illustrates", %{
    model: model,
    domain: domain
  } do
    pages = Pages.render(domain, [%{model | domain: domain.module}])
    dir = "settlement/reaction_rules"

    policy = pages["#{dir}/policies/report_on_close.md"]
    assert policy =~ "## Constraints\n\n- `only_reportable` — Zgłaszamy tylko usługi"
    assert policy =~ "issues `report` — illustrates `only_reportable`"

    assert pages["#{dir}/effects/send_report.md"] =~
             "- `within_limits` — Adapter pilnuje limitów zapytań i ponawia je"

    pm = pages["#{dir}/process_managers/chase.md"]
    assert pm =~ "## Invariants\n\n- `one_timer` — Wizyta ma najwyżej jedno przypomnienie naraz"
    assert pm =~ "## Constraints\n\n- `business_days`"
  end
end
