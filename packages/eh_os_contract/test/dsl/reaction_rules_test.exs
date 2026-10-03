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
  alias EhOsContract.{Model, Pages}

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

    effect :send_report, "Wyślij zgłoszenie", handles: :reported, idempotency: :event_id do
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
      scope :report_on_close
      issues :report
    end

    scenario "zamknięcie — przypomnienie za dzień",
      illustrates: [:one_timer, :business_days] do
      on :closed, %{reportable: true}
      scope :chase
      sets :due
    end
  """

  setup_all do
    %{model: compile_contract("ReactionRules", @visits)}
  end

  describe "the model" do
    test "keeps each reaction's rules, and each scenario what it illustrates", %{model: model} do
      [policy] = model.policies
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
          effect :send_report, "Wyślij", handles: :reported, idempotency: :event_id

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
            scope :report_on_close
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

      assert message =~ "S10:"
      assert message =~ "a command's scenario shows the rules it is refused on with `rejected`"
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
    found =
      for %Finding{rule: "prose-without-scenario"} = f <-
            Completeness.findings([EhOsContract.Fixtures.ReactionRules]),
          do: {f.message, Finding.place(f)}

    assert [
             {"constraint :one_answer of policy :report_on_close of " <> _,
              {"reaction_rules.ex", 19}},
             {"constraint :own_clinic of query :visits_of of " <> _, {"reaction_rules.ex", 41}}
           ] = Enum.sort_by(found, &elem(&1, 1))
  end

  test "the pages list each reaction's rules, and what a scenario illustrates", %{
    model: model
  } do
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

    domain = Model.fetch(EhOsContract.ReactionRulesTest.Domain)
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
