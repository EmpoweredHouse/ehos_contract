defmodule EhOsContract.ContractScenariosTest do
  @moduledoc """
  v2 plan, E5: **S1–S8 of v2 §6** — scenarios. Each refusal names the declaration's
  file and line, and has a control beside it that compiles.
  """

  use EhOsContract.DslCase, async: false

  # Line 4 of the file is the first line of `@unit`.
  @unit """
    aggregate :visit, "Wizyta" do
      identity :visit_id
      invariant :paid_in_full, "Zapłacono całość"

      command :record_payment, "Przyjęcie płatności", by: :reception, emits: :payment_recorded do
        field :amount, :integer
      end

      command :close, "Zamknięcie", by: [:reception, :manager], emits: :closed, rejects: :paid_in_full
      command :remind, "Przypomnienie", by: :manager, emits: :reminded

      event :payment_recorded, "Zapłacono" do
        field :amount, :integer
        field :paid_at, :timestamp, optional: true
      end

      event :closed, "Zamknięto", terminal: true
      event :reminded, "Przypomniano"
    end

    process :visit, "Wizyta" do
      correlate :visit_id
    end

    scenario "zapłacono za mało — zamknięcie odrzucone" do
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
          scenario "bez wyzwalacza" do
            expect :closed
          end

          scenario "dwa wyzwalacze" do
            command :close
            command :remind
            expect :closed
          end

          scenario "nieznana komenda" do
            command :cancel
            expect :closed
          end
        """)

      assert message =~
               ~s|S1: scenario "bez wyzwalacza" has no trigger; give it one command, on or query | <>
                 "(trigger_wrong.ex:34)"

      assert message =~
               ~s|S1: scenario "dwa wyzwalacze" has 2 triggers; a scenario has exactly one | <>
                 "(trigger_wrong.ex:38)"

      assert message =~
               ~s|S1: scenario "nieznana komenda": :cancel is not a command of this contract | <>
                 "(trigger_wrong.ex:45)"
    end

    test "two scenarios with one description" do
      message =
        refuse_contract("DescribedTwice", """
        #{@unit}
          scenario "zapłacono za mało — zamknięcie odrzucone" do
            command :remind
            expect :reminded
          end
        """)

      assert message =~
               ~s|S1: two scenarios are described "zapłacono za mało — zamknięcie odrzucone"; | <>
                 "each case needs its own words (described_twice.ex:34)"
    end

    test "an event two reactions handle needs target, and target must answer it" do
      message =
        refuse_contract("TargetWrong", """
        #{@unit}
          policy :remind_on_close, "Przypomnij", handles: :closed, issues: :remind
          policy :remind_again, "Przypomnij znowu", handles: :closed, issues: :remind

          scenario "zamknięcie — przypomnienie" do
            on :closed
            issues :remind
          end

          scenario "zamknięcie — obca polityka" do
            target :visit
            on :closed
            issues :remind
          end
        """)

      assert message =~
               ~s|S1: scenario "zamknięcie — przypomnienie": :closed is handled by policy | <>
                 ":remind_on_close, policy :remind_again; name one with target (target_wrong.ex:38)"

      assert message =~
               ~s|S1: scenario "zamknięcie — obca polityka": target :visit does not answer :closed | <>
                 "(target_wrong.ex:42)"
    end

    test "control: target picks the reaction, and the model keeps the one trigger and its target" do
      model =
        compile_contract("TargetRight", """
        #{@unit}
          policy :remind_on_close, "Przypomnij", handles: :closed, issues: :remind
          policy :remind_again, "Przypomnij znowu", handles: :closed, issues: :remind

          scenario "zamknięcie — przypomnienie" do
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
          scenario "zapłacono" do
            given :reminded, %{note: "x"}
            given :payment_recorded, %{}
            command :record_payment, %{amount: 100, currency: :pln}
            expect :payment_recorded, %{amount: 100}
          end

          policy :remind_on_close, "Przypomnij", handles: :closed, issues: :remind

          scenario "polityka ze stanem" do
            given :closed
            on :closed
            issues :remind
          end
        """)

      where = ~s|scenario "zapłacono" (aggregate :visit)|

      assert message =~ "S3: #{where}: event :reminded has no field :note (data_wrong.ex:35)"
      assert message =~ "S3: #{where}: event :payment_recorded needs :amount (data_wrong.ex:36)"

      assert message =~
               "S3: #{where}: command :record_payment has no field :currency (data_wrong.ex:37)"

      assert message =~
               ~s|S2: scenario "polityka ze stanem" (policy :remind_on_close): a policy keeps no | <>
                 "state, so it takes no given (data_wrong.ex:44)"
    end

    test "the data of what a process manager or a boundary is given" do
      message =
        refuse_contract("GivenDataWrong", """
        #{@unit}
          process_manager :chase, "Pogoń" do
            correlate :visit_id
            starts_on :payment_recorded, issues: :remind
            ends_on :closed
          end

          scenario "zamknięto — pogoń się kończy" do
            given :payment_recorded, %{amont: 100}
            on :closed
            ended true
          end

          dcb :slot, "Termin" do
            identity :visit_id
            command :hold, "Wstrzymanie", by: :reception, emits: :held
            event :held, "Wstrzymano"
            consults :payment_recorded, match: :visit_id
          end

          scenario "wstrzymano po płatności" do
            given :payment_recorded, %{amount: "sto"}
            command :hold
            expect :held
          end
        """)

      manager = ~s|scenario "zamknięto — pogoń się kończy" (process manager :chase)|

      assert message =~
               "S3: #{manager}: event :payment_recorded has no field :amont (given_data_wrong.ex:41)"

      assert message =~
               "S3: #{manager}: event :payment_recorded needs :amount (given_data_wrong.ex:41)"

      assert message =~
               ~s|S3: scenario "wstrzymano po płatności" (dcb :slot): event :payment_recorded, | <>
                 ~s|field :amount: "sto" is not an :integer (given_data_wrong.ex:54)|
    end

    test "a given the unit does not keep is refused" do
      message =
        refuse_contract("GivenWrong", """
        #{@unit}
          scenario "przypomniano" do
            given :visit_booked
            command :remind
            expect :reminded
          end
        """)

      assert message =~
               ~s|S2: scenario "przypomniano" (aggregate :visit): given :visit_booked is neither | <>
                 "an event of the unit nor one it consults (given_wrong.ex:35)"
    end

    test "a timestamp is an ISO 8601 string, never a struct" do
      message =
        refuse_contract("TimeWrong", """
        #{@unit}
          scenario "zapłacono wczoraj" do
            given :payment_recorded, %{amount: 100, paid_at: ~U[2026-09-01 09:00:00Z]}
            given :payment_recorded, %{amount: 100, paid_at: "wczoraj"}
            given :payment_recorded, %{amount: "sto"}
            command :remind
            expect :reminded
          end
        """)

      assert message =~
               "field :paid_at: DateTime is a struct; write an ISO 8601 string, " <>
                 ~s|"2026-09-01T09:00:00Z", since the model is plain data (time_wrong.ex:35)|

      assert message =~
               ~s|field :paid_at: "wczoraj" is not an ISO 8601 timestamp with an offset| <>
                 ~s|, "2026-09-01T09:00:00Z" (time_wrong.ex:36)|

      assert message =~ ~s|field :amount: "sto" is not an :integer (time_wrong.ex:37)|
    end

    test "an empty identifier is refused here, as dispatch refuses it" do
      # Found in the review of E11a: the codec refused `""` for an `:id` at dispatch,
      # while a scenario carrying one compiled and failed only when its test ran.
      message =
        refuse_contract("EmptyId", """
        #{@unit}
          scenario "zapłacono bez wizyty" do
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
                 scenario "zapłacono dwa razy" do
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
          scenario "przypomnienie odrzucone" do
            command :remind
            rejected :paid_in_full
          end

          scenario "przypomnienie zamyka" do
            command :remind
            expect :closed
          end
        """)

      assert message =~
               ~s|S4: scenario "przypomnienie odrzucone" (aggregate :visit): rejected | <>
                 ":paid_in_full is not among what command :remind rejects, [] (outcome_wrong.ex:34)"

      assert message =~
               ~s|S5: scenario "przypomnienie zamyka" (aggregate :visit): expects :closed, which | <>
                 "command :remind does not emit (outcome_wrong.ex:41)"
    end
  end

  describe "S6: trigger and outcome fit the target" do
    test "a command with no outcome, or with both, and reactions' words after a command" do
      message =
        refuse_contract("CommandOutcome", """
        #{@unit}
          scenario "zamknięcie bez wyniku" do
            command :close
          end

          scenario "zamknięcie na dwa sposoby" do
            command :close
            expect :closed
            rejected :paid_in_full
          end

          scenario "zamknięcie wydaje komendę" do
            command :close
            expect :closed
            issues :remind
          end
        """)

      assert message =~
               ~s|S6: scenario "zamknięcie bez wyniku" (aggregate :visit): after a command, | <>
                 "expect the events or say it is rejected (command_outcome.ex:34)"

      assert message =~
               ~s|S6: scenario "zamknięcie na dwa sposoby" (aggregate :visit): a command either | <>
                 "emits or is rejected; not both (command_outcome.ex:38)"

      assert message =~
               ~s|S6: scenario "zamknięcie wydaje komendę" (aggregate :visit): issues belongs to | <>
                 "a reaction's scenario, not to a command to a unit (command_outcome.ex:47)"
    end

    test "a policy that issues nothing, what it does not issue, and an effect" do
      message =
        refuse_contract("ReactionOutcome", """
        #{@unit}
          policy :remind_on_close, "Przypomnij", handles: :closed, issues: :remind
          effect :notify, "Powiadom", handles: :reminded, idempotency: [key: :event_id, owner: :downstream]

          scenario "zamknięcie — nic" do
            on :closed
          end

          scenario "zamknięcie — zamknięcie" do
            on :closed
            issues :close
          end

          scenario "przypomniano — powiadomienie" do
            on :reminded
          end
        """)

      assert message =~
               ~s|S6: scenario "zamknięcie — nic" (policy :remind_on_close): after an event, a | <>
                 "policy issues something; say what (reaction_outcome.ex:37)"

      assert message =~
               ~s|S6: scenario "zamknięcie — zamknięcie" (policy :remind_on_close): issues :close, | <>
                 "which it does not issue (reaction_outcome.ex:43)"

      assert message =~
               ~s|S6: scenario "przypomniano — powiadomienie": effect :notify cannot be a | <>
                 "scenario's target: an effect's outcome is outside the log (reaction_outcome.ex:46)"
    end

    test "a process manager's timers and its end are the ones its declaration names" do
      message =
        refuse_contract("ManagerOutcome", """
        #{@unit}
          process_manager :chase, "Pogoń" do
            correlate :visit_id
            starts_on :payment_recorded, sets: :later
            on :reminded, cancels: :later
            timer :later, "Later", wait: {1, :day}, issues: :remind
            ends_on :closed
          end

          scenario "zapłacono — pogoń" do
            on :payment_recorded, %{amount: 100}
            sets :never
            ended true
          end
        """)

      where = ~s|scenario "zapłacono — pogoń" (process manager :chase)|

      assert message =~
               "S6: #{where}: :payment_recorded does not set timer :never (manager_outcome.ex:44)"

      assert message =~
               "S6: #{where}: :payment_recorded is not among what it ends on (manager_outcome.ex:42)"
    end

    test "control: a process manager's scenario, from start to end" do
      assert [_, %{target: %{kind: :process_manager}, sets: [:later]}, %{ended: true}] =
               compile_contract("ManagerScenarios", """
               #{@unit}
                 process_manager :chase, "Pogoń" do
                   correlate :visit_id
                   starts_on :payment_recorded, sets: :later
                   on :reminded, cancels: :later
                   timer :later, "Later", wait: {1, :day}, issues: :remind
                   ends_on :closed
                 end

                 scenario "zapłacono — pogoń się zaczyna" do
                   on :payment_recorded, %{amount: 100}
                   sets :later
                 end

                 scenario "zamknięto — pogoń się kończy" do
                   given :payment_recorded, %{amount: 100}
                   on :closed
                   ended true
                 end
               """).scenarios
    end
  end

  describe "S6: a query's scenario answers (ESDM's read model scenario)" do
    @read """
      read_model :payments, "Płatności", projects: [:payment_recorded] do
        field :visit_id, :id
        field :amount, :integer
      end

      query :payments_of_visit, "Płatności wizyty", reads: :payments, by: :reception do
        param :visit_id, :id
      end

      query :last_payment, "Ostatnia płatność", reads: :payments, by: :reception, returns: :one do
        param :visit_id, :id
      end
    """

    test "no answer, two answers, the wrong shape, a field the row lacks, a given it does not project" do
      message =
        refuse_contract("QueryOutcome", """
        #{@unit}
        #{@read}
          scenario "płatności — bez odpowiedzi" do
            query :payments_of_visit, %{visit_id: "w-1"}
          end

          scenario "płatności — dwie odpowiedzi" do
            query :payments_of_visit, %{visit_id: "w-1"}
            answers []
            answers []
          end

          scenario "ostatnia płatność — lista" do
            query :last_payment, %{visit_id: "w-1"}
            answers [%{amount: 100}]
          end

          scenario "płatności — pole spoza wiersza" do
            given :closed
            query :payments_of_visit, %{visit_id: "w-1"}
            answers [%{amount: 100, method: :card}]
          end
        """)

      assert message =~
               ~s|S6: scenario "płatności — bez odpowiedzi" (query :payments_of_visit): after a | <>
                 "query, say what it answers (query_outcome.ex:47)"

      assert message =~
               ~s|S6: scenario "płatności — dwie odpowiedzi" (query :payments_of_visit): a query | <>
                 "answers once (query_outcome.ex:54)"

      assert message =~
               ~s|S6: scenario "ostatnia płatność — lista" (query :last_payment): answers one | <>
                 "row, a map, or nil, as the query returns one (query_outcome.ex:59)"

      assert message =~
               ~s|S3: scenario "płatności — pole spoza wiersza" (query :payments_of_visit): a row | <>
                 "of read model :payments has no field :method (query_outcome.ex:65)"

      assert message =~
               ~s|S2: scenario "płatności — pole spoza wiersza" (query :payments_of_visit): given | <>
                 ":closed is not an event read model :payments projects (query_outcome.ex:63)"
    end

    test "answers belongs to a query's scenario" do
      message =
        refuse_contract("AnswersElsewhere", """
        #{@unit}
          scenario "zamknięcie z odpowiedzią" do
            command :close
            expect :closed
            answers []
          end
        """)

      assert message =~
               ~s|S6: scenario "zamknięcie z odpowiedzią" (aggregate :visit): answers belongs to | <>
                 "a query's scenario, not to a command to a unit (answers_elsewhere.ex:37)"
    end

    test "control: rows of the read model, one row or nil, and the model keeps them as a list" do
      assert [_, many, one, none] =
               compile_contract("QueryScenarios", """
               #{@unit}
               #{@read}
                 scenario "płatności wizyty" do
                   given :payment_recorded, %{visit_id: "w-1", amount: 100}
                   query :payments_of_visit, %{visit_id: "w-1"}
                   answers [%{visit_id: "w-1", amount: 100}]
                 end

                 scenario "ostatnia płatność" do
                   given :payment_recorded, %{visit_id: "w-1", amount: 100}
                   query :last_payment, %{visit_id: "w-1"}
                   answers %{amount: 100}
                 end

                 scenario "brak płatności" do
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
          policy :remind_on_close, "Przypomnij", handles: :closed, issues: :remind

          scenario "menedżer płaci" do
            actor :manager
            command :record_payment, %{amount: 100}
            expect :payment_recorded
          end

          scenario "recepcja przypomina" do
            actor :reception
            on :closed
            issues :remind
          end
        """)

      assert message =~
               ~s|S7: scenario "menedżer płaci" (aggregate :visit): actor :manager is not among | <>
                 "who may issue :record_payment, [:reception] (actor_wrong.ex:36)"

      assert message =~
               ~s|S7: scenario "recepcja przypomina" (policy :remind_on_close): only a command's | <>
                 "scenario names an actor (actor_wrong.ex:42)"
    end

    test "control: an actor in by: compiles" do
      assert [_, %{actor: :manager}] =
               compile_contract("ActorRight", """
               #{@unit}
                 scenario "menedżer zamyka" do
                   actor :manager
                   command :close
                   expect :closed
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
