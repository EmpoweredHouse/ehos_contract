defmodule EhOsContract.ContractScenariosTest do
  @moduledoc """
  v2 plan, E5: **S1–S8 of v2 §6** — scenarios. Each refusal names the declaration's
  file and line, and has a control beside it that compiles.
  """

  use EhOsContract.DslCase, async: false

  # Line 4 of the file is the first line of `@unit`.
  @unit """
    aggregate :visit, "Visit" do
      identity :visit_id
      invariant :paid_in_full, "Paid in full"

      command :record_payment, "Recording a payment", by: :reception, emits: :payment_recorded do
        field :amount, :integer
      end

      command :close, "Closing", by: [:reception, :manager], emits: :closed, rejects: :paid_in_full
      command :remind, "Reminder", by: :manager, emits: :reminded

      event :payment_recorded, "Paid" do
        field :amount, :integer
        field :paid_at, :timestamp, optional: true
      end

      event :closed, "Closed"
      event :reminded, "Reminded"
    end

    scenario "paid too little — closing rejected" do
      given :payment_recorded, %{amount: 100}
      command :close
      rejected :paid_in_full
    end
  """

  describe "S1: one trigger, which resolves" do
    test "no trigger, two triggers, and a trigger nothing answers are refused" do
      message =
        refuse_contract("TriggerWrong", """
        #{@unit}
          scenario "without a trigger" do
            expect :closed
          end

          scenario "two triggers" do
            command :close
            command :remind
            expect :closed
          end

          scenario "an unknown command" do
            command :cancel
            expect :closed
          end
        """)

      assert message =~
               ~s|S1: scenario "without a trigger" has no trigger; give it one command, on, query or record | <>
                 "(trigger_wrong.ex:30)"

      assert message =~
               ~s|S1: scenario "two triggers" has 2 triggers; a scenario has exactly one | <>
                 "(trigger_wrong.ex:34)"

      assert message =~
               ~s|S1: scenario "an unknown command": :cancel is not a command of this contract | <>
                 "(trigger_wrong.ex:41)"
    end

    test "two scenarios with one description" do
      message =
        refuse_contract("DescribedTwice", """
        #{@unit}
          scenario "paid too little — closing rejected" do
            command :remind
            expect :reminded
          end
        """)

      assert message =~
               ~s|S1: two scenarios are described "paid too little — closing rejected"; | <>
                 "each case needs its own words (described_twice.ex:30)"
    end

    test "an event two reactions handle needs target, and target must answer it" do
      message =
        refuse_contract("TargetWrong", """
        #{@unit}
          policy :remind_on_close, "Remind", handles: :closed, issues: :remind
          policy :remind_again, "Remind again", handles: :closed, issues: :remind

          scenario "closing — reminder" do
            on :closed
            issues :remind
          end

          scenario "closing — a foreign policy" do
            target :visit
            on :closed
            issues :remind
          end
        """)

      assert message =~
               ~s|S1: scenario "closing — reminder": :closed is handled by policy | <>
                 ":remind_on_close, policy :remind_again; name one with target (target_wrong.ex:34)"

      assert message =~
               ~s|S1: scenario "closing — a foreign policy": target :visit does not answer :closed | <>
                 "(target_wrong.ex:38)"
    end

    test "control: target picks the reaction, and the model keeps the one trigger and its target" do
      model =
        compile_contract("TargetRight", """
        #{@unit}
          policy :remind_on_close, "Remind", handles: :closed, issues: :remind
          policy :remind_again, "Remind again", handles: :closed, issues: :remind

          scenario "closing — reminder" do
            target :remind_again
            on :closed
            issues :remind
          end
        """)

      assert [
               %{target: %{kind: :aggregate, name: :visit}, trigger: %{kind: :command}},
               %{
                 target: %{kind: :policy, name: :remind_again},
                 trigger: %{kind: :on, name: :closed, data: %{}},
                 issues: [%{command: :remind, data: %{}}]
               }
             ] = model.scenarios
    end
  end

  describe "S2 and S3: what is given, and the data" do
    test "a given the unit does not keep, a field nobody declared, and a missing one" do
      message =
        refuse_contract("DataWrong", """
        #{@unit}
          scenario "paid" do
            given :reminded, %{note: "x"}
            given :payment_recorded, %{}
            command :record_payment, %{amount: 100, currency: :pln}
            expect :payment_recorded, %{amount: 100}
          end

          policy :remind_on_close, "Remind", handles: :closed, issues: :remind

          scenario "a policy with state" do
            given :closed
            on :closed
            issues :remind
          end
        """)

      where = ~s|scenario "paid" (aggregate :visit)|

      assert message =~ "S3: #{where}: event :reminded has no field :note (data_wrong.ex:31)"
      assert message =~ "S3: #{where}: event :payment_recorded needs :amount (data_wrong.ex:32)"

      assert message =~
               "S3: #{where}: command :record_payment has no field :currency (data_wrong.ex:33)"

      assert message =~
               ~s|S2: scenario "a policy with state" (policy :remind_on_close): a policy keeps no | <>
                 "state, so it takes no given (data_wrong.ex:40)"
    end

    test "the data of what a process manager or a boundary is given" do
      message =
        refuse_contract("GivenDataWrong", """
        #{@unit}
          process_manager :chase, "Chase" do
            correlate :visit_id
            starts_on :payment_recorded, issues: :remind
            ends_on :closed
          end

          scenario "closed — the chase ends" do
            given :payment_recorded, %{amont: 100}
            on :closed
            ended true
          end

          dcb :slot, "Slot" do
            identity :visit_id
            command :hold, "Holding", by: :reception, emits: :held
            event :held, "Held"
            consults :payment_recorded, match: :visit_id
          end

          scenario "held after a payment" do
            given :payment_recorded, %{amount: "a hundred"}
            command :hold
            expect :held
          end
        """)

      manager = ~s|scenario "closed — the chase ends" (process manager :chase)|

      assert message =~
               "S3: #{manager}: event :payment_recorded has no field :amont (given_data_wrong.ex:37)"

      assert message =~
               "S3: #{manager}: event :payment_recorded needs :amount (given_data_wrong.ex:37)"

      assert message =~
               ~s|S3: scenario "held after a payment" (dcb :slot): event :payment_recorded, | <>
                 ~s|field :amount: "a hundred" is not an :integer (given_data_wrong.ex:50)|
    end

    test "a given the unit does not keep is refused" do
      message =
        refuse_contract("GivenWrong", """
        #{@unit}
          scenario "reminded" do
            given :visit_booked
            command :remind
            expect :reminded
          end
        """)

      assert message =~
               ~s|S2: scenario "reminded" (aggregate :visit): given :visit_booked is neither | <>
                 "an event of the unit nor one it consults (given_wrong.ex:31)"
    end

    test "a timestamp is an ISO 8601 string, never a struct" do
      message =
        refuse_contract("TimeWrong", """
        #{@unit}
          scenario "paid yesterday" do
            given :payment_recorded, %{amount: 100, paid_at: ~U[2026-09-01 09:00:00Z]}
            given :payment_recorded, %{amount: 100, paid_at: "yesterday"}
            given :payment_recorded, %{amount: "a hundred"}
            command :remind
            expect :reminded
          end
        """)

      assert message =~
               "field :paid_at: DateTime is a struct; write an ISO 8601 string, " <>
                 ~s|"2026-09-01T09:00:00Z", since the model is plain data (time_wrong.ex:31)|

      assert message =~
               ~s|field :paid_at: "yesterday" is not an ISO 8601 timestamp with an offset| <>
                 ~s|, "2026-09-01T09:00:00Z" (time_wrong.ex:32)|

      assert message =~ ~s|field :amount: "a hundred" is not an :integer (time_wrong.ex:33)|
    end

    test "an empty identifier is refused here, as dispatch refuses it" do
      # Found in the review of E11a: the codec refused `""` for an `:id` at dispatch,
      # while a scenario carrying one compiled and failed only when its test ran.
      message =
        refuse_contract("EmptyId", """
        #{@unit}
          scenario "paid without a visit" do
            given :payment_recorded, %{visit_id: "", amount: 100}
            command :remind
            expect :reminded
          end
        """)

      assert message =~ ~s|field :visit_id: "" is not an identifier, which names something|
    end

    test "control: the identity is the scenario's own, and a timestamp is a string" do
      assert [_, %{given: [%{data: %{paid_at: "2026-09-01T09:00:00Z"}}, _]}] =
               compile_contract("DataRight", """
               #{@unit}
                 scenario "paid twice" do
                   given :payment_recorded, %{amount: 100, paid_at: "2026-09-01T09:00:00Z"}
                   given :payment_recorded, %{visit_id: "w-1", amount: 50}
                   command :close, %{visit_id: "w-1"}
                   expect :closed
                 end
               """).scenarios
    end
  end

  describe "S4 and S5: what a command's scenario may expect" do
    test "a rejection the command does not declare, and an event it does not emit" do
      message =
        refuse_contract("OutcomeWrong", """
        #{@unit}
          scenario "reminder rejected" do
            command :remind
            rejected :paid_in_full
          end

          scenario "the reminder closes" do
            command :remind
            expect :closed
          end
        """)

      assert message =~
               ~s|S4: scenario "reminder rejected" (aggregate :visit): rejected | <>
                 ":paid_in_full is not among what command :remind rejects, [] (outcome_wrong.ex:30)"

      assert message =~
               ~s|S5: scenario "the reminder closes" (aggregate :visit): expects :closed, which | <>
                 "command :remind does not emit (outcome_wrong.ex:37)"
    end
  end

  describe "S6: trigger and outcome fit the target" do
    test "a command with no outcome, or with both, and reactions' words after a command" do
      message =
        refuse_contract("CommandOutcome", """
        #{@unit}
          scenario "closing without an outcome" do
            command :close
          end

          scenario "closing two ways" do
            command :close
            expect :closed
            rejected :paid_in_full
          end

          scenario "closing issues a command" do
            command :close
            expect :closed
            issues :remind
          end
        """)

      assert message =~
               ~s|S6: scenario "closing without an outcome" (aggregate :visit): after a command, | <>
                 "expect the events or say it is rejected (command_outcome.ex:30)"

      assert message =~
               ~s|S6: scenario "closing two ways" (aggregate :visit): a command either | <>
                 "emits or is rejected; not both (command_outcome.ex:34)"

      assert message =~
               ~s|S6: scenario "closing issues a command" (aggregate :visit): issues belongs to | <>
                 "a reaction's scenario, not to a command to a unit (command_outcome.ex:43)"
    end

    test "a policy that issues nothing, what it does not issue, and an effect" do
      message =
        refuse_contract("ReactionOutcome", """
        #{@unit}
          policy :remind_on_close, "Remind", handles: :closed, issues: :remind
          effect :notify, "Notify", handles: :reminded, idempotency: [key: :event_id, owner: :downstream]

          scenario "closing — nothing" do
            on :closed
          end

          scenario "closing — closing" do
            on :closed
            issues :close
          end

          scenario "reminded — notification" do
            on :reminded
          end
        """)

      assert message =~
               ~s|S6: scenario "closing — nothing" (policy :remind_on_close): after an event, a | <>
                 "policy issues something; say what (reaction_outcome.ex:33)"

      assert message =~
               ~s|S6: scenario "closing — closing" (policy :remind_on_close): issues :close, | <>
                 "which it does not issue (reaction_outcome.ex:39)"

      assert message =~
               ~s|S6: scenario "reminded — notification": effect :notify cannot be a | <>
                 "scenario's target: an effect's outcome is outside the log (reaction_outcome.ex:42)"
    end

    test "a process manager's timers and its end are the ones its declaration names" do
      message =
        refuse_contract("ManagerOutcome", """
        #{@unit}
          process_manager :chase, "Chase" do
            correlate :visit_id
            starts_on :payment_recorded, sets: :later
            on :reminded, cancels: :later
            timer :later, "Later", wait: {1, :day}, issues: :remind
            ends_on :closed
          end

          scenario "paid — chase" do
            on :payment_recorded, %{amount: 100}
            sets :never
            ended true
          end
        """)

      where = ~s|scenario "paid — chase" (process manager :chase)|

      assert message =~
               "S6: #{where}: :payment_recorded does not set timer :never (manager_outcome.ex:40)"

      assert message =~
               "S6: #{where}: :payment_recorded is not among what it ends on (manager_outcome.ex:38)"
    end

    test "control: a process manager's scenario, from start to end" do
      assert [_, %{target: %{kind: :process_manager}, sets: [:later]}, %{ended: true}] =
               compile_contract("ManagerScenarios", """
               #{@unit}
                 process_manager :chase, "Chase" do
                   correlate :visit_id
                   starts_on :payment_recorded, sets: :later
                   on :reminded, cancels: :later
                   timer :later, "Later", wait: {1, :day}, issues: :remind
                   ends_on :closed
                 end

                 scenario "paid — the chase starts" do
                   on :payment_recorded, %{amount: 100}
                   sets :later
                 end

                 scenario "closed — the chase ends" do
                   given :payment_recorded, %{amount: 100}
                   on :closed
                   ended true
                 end
               """).scenarios
    end
  end

  describe "S6: a query's scenario answers (ESDM's read model scenario)" do
    @read """
      read_model :payments, "Payments", projects: [:payment_recorded] do
        field :visit_id, :id
        field :amount, :integer
      end

      query :payments_of_visit, "A visit's payments", reads: :payments, by: :reception do
        param :visit_id, :id
      end

      query :last_payment, "Last payment", reads: :payments, by: :reception, returns: :one do
        param :visit_id, :id
      end
    """

    test "no answer, two answers, the wrong shape, a field the row lacks, a given it does not project" do
      message =
        refuse_contract("QueryOutcome", """
        #{@unit}
        #{@read}
          scenario "payments — no answer" do
            query :payments_of_visit, %{visit_id: "w-1"}
          end

          scenario "payments — two answers" do
            query :payments_of_visit, %{visit_id: "w-1"}
            answers []
            answers []
          end

          scenario "last payment — a list" do
            query :last_payment, %{visit_id: "w-1"}
            answers [%{amount: 100}]
          end

          scenario "payments — a field outside the row" do
            given :closed
            query :payments_of_visit, %{visit_id: "w-1"}
            answers [%{amount: 100, method: :card}]
          end
        """)

      assert message =~
               ~s|S6: scenario "payments — no answer" (query :payments_of_visit): after a | <>
                 "query, say what it answers (query_outcome.ex:43)"

      assert message =~
               ~s|S6: scenario "payments — two answers" (query :payments_of_visit): a query | <>
                 "answers once (query_outcome.ex:50)"

      assert message =~
               ~s|S6: scenario "last payment — a list" (query :last_payment): answers one | <>
                 "row, a map, or nil, as the query returns one (query_outcome.ex:55)"

      assert message =~
               ~s|S3: scenario "payments — a field outside the row" (query :payments_of_visit): a row | <>
                 "of read model :payments has no field :method (query_outcome.ex:61)"

      assert message =~
               ~s|S2: scenario "payments — a field outside the row" (query :payments_of_visit): given | <>
                 ":closed is not an event read model :payments projects (query_outcome.ex:59)"
    end

    test "answers belongs to a query's scenario" do
      message =
        refuse_contract("AnswersElsewhere", """
        #{@unit}
          scenario "closing with an answer" do
            command :close
            expect :closed
            answers []
          end
        """)

      assert message =~
               ~s|S6: scenario "closing with an answer" (aggregate :visit): answers belongs to | <>
                 "a query's scenario, not to a command to a unit (answers_elsewhere.ex:33)"
    end

    test "control: rows of the read model, one row or nil, and the model keeps them as a list" do
      assert [_, many, one, none] =
               compile_contract("QueryScenarios", """
               #{@unit}
               #{@read}
                 scenario "a visit's payments" do
                   given :payment_recorded, %{visit_id: "w-1", amount: 100}
                   query :payments_of_visit, %{visit_id: "w-1"}
                   answers [%{visit_id: "w-1", amount: 100}]
                 end

                 scenario "last payment" do
                   given :payment_recorded, %{visit_id: "w-1", amount: 100}
                   query :last_payment, %{visit_id: "w-1"}
                   answers %{amount: 100}
                 end

                 scenario "no payment" do
                   query :last_payment, %{visit_id: "w-1"}
                   answers nil
                 end
               """).scenarios

      assert %{target: %{kind: :query, name: :payments_of_visit}, answers: [%{amount: 100}]} =
               many

      assert %{answers: [%{amount: 100}]} = one
      assert %{answers: []} = none
    end

    test "a command's scenario has no answers key, so the word moved no version" do
      refute Map.has_key?(hd(compile_contract("NoAnswers", @unit).scenarios), :answers)
    end
  end

  describe "S7: the actor" do
    test "an actor who may not issue the command, and an actor on a reaction" do
      message =
        refuse_contract("ActorWrong", """
        #{@unit}
          policy :remind_on_close, "Remind", handles: :closed, issues: :remind

          scenario "the manager pays" do
            actor :manager
            command :record_payment, %{amount: 100}
            expect :payment_recorded
          end

          scenario "reception reminds" do
            actor :reception
            on :closed
            issues :remind
          end
        """)

      assert message =~
               ~s|S7: scenario "the manager pays" (aggregate :visit): actor :manager is not among | <>
                 "who may issue :record_payment, [:reception] (actor_wrong.ex:32)"

      assert message =~
               ~s|S7: scenario "reception reminds" (policy :remind_on_close): only a command's | <>
                 "or a recording's scenario names an actor (actor_wrong.ex:38)"
    end

    test "a person named with as: without an actor, and on a reaction (plan DD, A1, #247)" do
      message =
        refuse_contract("PersonWrong", """
        #{@unit}
          policy :remind_on_close, "Remind", handles: :closed, issues: :remind

          scenario "someone closes" do
            as "reception-ola"
            command :close
            expect :closed
          end

          scenario "reminder" do
            as "reception-ola"
            on :closed
            issues :remind
          end
        """)

      assert message =~
               ~s|S7: scenario "someone closes" (aggregate :visit): as: names a person only beside | <>
                 "an actor:"

      assert message =~
               ~s|S7: scenario "reminder" (policy :remind_on_close): only a command's | <>
                 "scenario names a person with as:"
    end

    test "control: an actor in by: compiles" do
      assert [_, %{actor: :manager}] =
               compile_contract("ActorRight", """
               #{@unit}
                 scenario "the manager closes" do
                   actor :manager
                   command :close
                   expect :closed
                 end
               """).scenarios
    end
  end

  describe "a recording's scenario (issue #430)" do
    @recorded """
      aggregate :payment, "Payment" do
        identity :payment_id
        invariant :paid_once, "Paid once"

        command :request, "Request", by: :clerk, emits: :requested, rejects: :paid_once

        event :requested, "Requested"

        event :collected, "Collected", recorded_by: :gateway do
          field :amount, :integer
        end
      end

      scenario "requested twice" do
        given :requested
        command :request
        rejected :paid_once
      end
    """

    test "a recording of an event no actor records, and one of no event, are refused (S1)" do
      message =
        refuse_contract("RecordUnresolved", """
        #{@recorded}
          scenario "recording a decided event" do
            actor :gateway
            record :requested
            expect :requested
          end
        """)

      assert message =~
               ~s|S1: scenario "recording a decided event": :requested is not an event of this | <>
                 "contract that an actor records (recorded_by:)"
    end

    test "an actor missing or outside recorded_by:, and a person named with as:, are refused (S7)" do
      message =
        refuse_contract("RecordActor", """
        #{@recorded}
          scenario "nobody records" do
            record :collected, %{amount: 1}
            expect :collected
          end

          scenario "the clerk records" do
            actor :clerk
            record :collected, %{amount: 1}
            expect :collected
          end

          scenario "a person records" do
            actor :gateway
            as "gateway-1"
            record :collected, %{amount: 1}
            expect :collected
          end
        """)

      assert message =~
               ~s|S7: scenario "nobody records" (aggregate :payment): a recording names who | <>
                 "records it with actor:, one of [:gateway]"

      assert message =~
               ~s|S7: scenario "the clerk records" (aggregate :payment): actor :clerk is not | <>
                 "among who may record :collected, [:gateway]"

      assert message =~
               ~s|S7: scenario "a person records" (aggregate :payment): only a command's | <>
                 "scenario names a person with as:"
    end

    test "illustrates: on a recording is refused, naming what shows its refusal (S10)" do
      message =
        refuse_contract("RecordIllustrates", """
        #{@recorded}
          scenario "the gateway records, illustrating" do
            actor :gateway
            illustrates :paid_once
            record :collected, %{amount: 1}
            expect :collected
          end
        """)

      assert message =~
               ~s|S10: scenario "the gateway records, illustrating" names rules in | <>
                 "illustrates:, but a recording's scenario shows the value's invariant it is " <>
                 "refused on with `rejected`"
    end

    test "another event expected, no outcome, both outcomes and missing data are refused" do
      message =
        refuse_contract("RecordOutcome", """
        #{@recorded}
          scenario "records another" do
            actor :gateway
            record :collected, %{amount: 1}
            expect :requested
          end

          scenario "records into nothing" do
            actor :gateway
            record :collected, %{amount: 1}
          end

          scenario "records and is refused" do
            actor :gateway
            record :collected, %{amount: 1}
            expect :collected
            rejected :not_negative
          end

          scenario "records without its data" do
            actor :gateway
            record :collected
            expect :collected
          end
        """)

      assert message =~
               ~s|S5: scenario "records another" (aggregate :payment): expects :requested, and a | <>
                 "recording appends only the event it records, :collected"

      assert message =~
               ~s|S6: scenario "records into nothing" (aggregate :payment): after a recording, | <>
                 "expect the event or say it is rejected"

      assert message =~
               ~s|S6: scenario "records and is refused" (aggregate :payment): a recording either | <>
                 "appends or is rejected; not both"

      assert message =~
               ~s|S3: scenario "records without its data" (aggregate :payment): event | <>
                 ":collected needs :amount"
    end

    test "a recording's rejected covers no invariant of its unit (S8)" do
      [before, _scenario] = String.split(@recorded, "\n  scenario ", parts: 2)

      message =
        refuse_contract("RecordNotCovering", """
        #{before}
          scenario "refused on the unit's invariant" do
            actor :gateway
            record :collected, %{amount: 1}
            rejected :paid_once
          end
        """)

      assert message =~
               "S8: invariant :paid_once of aggregate :payment has no scenario in which a " <>
                 "command is rejected on it"
    end

    test "control: a recording by an actor of recorded_by: compiles, with its trigger" do
      assert [_, %{actor: :gateway, trigger: %{kind: :record, name: :collected}}] =
               compile_contract("RecordRight", """
               #{@recorded}
                 scenario "the gateway records" do
                   actor :gateway
                   given :requested
                   record :collected, %{amount: 1}
                   expect :collected, %{amount: 1}
                 end
               """).scenarios
    end
  end

  describe "S8: every invariant has a scenario rejected on it" do
    test "removing the one rejected scenario breaks the compilation and names the invariant" do
      [before, _scenario] = String.split(@unit, "\n  scenario ", parts: 2)

      message = refuse_contract("Uncovered", before)

      assert message =~
               "S8: invariant :paid_in_full of aggregate :visit has no scenario in which a " <>
                 "command is rejected on it (uncovered.ex:6)"
    end

    test "control: the same contract with it compiles" do
      assert %{scenarios: [%{rejected: :paid_in_full}]} = compile_contract("Covered", @unit)
    end
  end
end
