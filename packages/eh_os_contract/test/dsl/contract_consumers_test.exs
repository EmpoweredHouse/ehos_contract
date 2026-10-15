defmodule EhOsContract.ContractConsumersTest do
  @moduledoc """
  v2 plan, E4: **P1–P5 of v2 §6** — what reacts to events, and what is read. Each
  refusal names the declaration's file and line, and has a control beside it that
  compiles.
  """

  use EhOsContract.DslCase, async: false

  @unit """
    aggregate :visit, "Wizyta" do
      identity :visit_id
      command :close_visit, "Zamknięcie wizyty", by: :reception, emits: :visit_closed
      command :remind, "Przypomnienie", by: :reception, emits: :reminded
      event :visit_closed, "Wizyta zamknięta"
      event :reminded, "Przypomniano"
    end
  """

  describe "P1: a policy handles known events and issues local commands" do
    test "an unknown event and a foreign command are refused" do
      message =
        refuse_contract("PolicyWrong", """
        #{@unit}
          policy :remind_on_close, "Przypomnij po zamknięciu",
            handles: [:visit_closed, :visit_lost],
            issues: [:remind, :send_invoice]
        """)

      assert message =~
               "P1: policy :remind_on_close handles :visit_lost, which is neither an event of this " <>
                 "contract nor one it consumes (policy_wrong.ex:12)"

      assert message =~
               "P1: policy :remind_on_close issues :send_invoice, which is not a command of this " <>
                 "contract (policy_wrong.ex:12)"
    end

    # Plan DD, C1 (#304): `handles: []` met `required:`, and a policy that handles
    # nothing never runs, yet dispatch would have let it issue what it names.
    test "a policy that handles no event is refused" do
      message =
        refuse_contract("PolicyHandlesNothing", """
        #{@unit}
          policy :remind_on_nothing, "Przypomnij bez powodu", handles: [], issues: :remind
        """)

      assert message =~
               "P1: policy :remind_on_nothing handles no event, so it never runs; name the events " <>
                 "it reacts to (policy_handles_nothing.ex:12)"
    end

    test "an effect that handles no event is refused" do
      message =
        refuse_contract("EffectHandlesNothing", """
        #{@unit}
          effect :notify_nobody, "Powiadom bez powodu", handles: [], delivery: :in_transaction
        """)

      assert message =~
               "P1: effect :notify_nobody handles no event, so it never runs; name the events " <>
                 "it reacts to (effect_handles_nothing.ex:12)"
    end

    test "control: a policy on a consumed event compiles" do
      assert %{policies: [%{handles: [:visit_booked], issues: [:remind]}]} =
               compile_contract("PolicyOnConsumed", """
                 consumes Clinic.Contracts.Booking, :visit_booked

               #{@unit}
                 policy :remind_on_booking, "Przypomnij po rezerwacji",
                   handles: :visit_booked,
                   issues: :remind
               """)
    end
  end

  describe "P2 and P3: an effect's external call, and delivery at least once" do
    test "an external call in the transaction, and at least once without idempotency" do
      message =
        refuse_contract("EffectWrong", """
        #{@unit}
          effect :notify, "Powiadom", handles: :visit_closed, calls: :mail, delivery: :in_transaction
          effect :notify_again, "Powiadom ponownie", handles: :visit_closed, calls: :mail

          policy :remind_later, "Przypomnij później",
            handles: :visit_closed,
            issues: :remind,
            delivery: :at_least_once
        """)

      assert message =~
               "P2: effect :notify calls [:mail], so it cannot run :in_transaction: an external " <>
                 "call is not rolled back with the append (effect_wrong.ex:12)"

      assert message =~
               "P3: effect :notify_again is delivered :at_least_once, so it names its " <>
                 "idempotency: what makes a second delivery harmless (effect_wrong.ex:13)"

      assert message =~ "P3: policy :remind_later is delivered :at_least_once"
      assert message =~ "(effect_wrong.ex:15)"
    end

    test "control: v2 §4.6's effect, and a process manager without idempotency, compile" do
      assert %{
               effects: [%{idempotency: %{key: :event_id, owner: :downstream}}],
               process_managers: [%{idempotency: nil}]
             } =
               compile_contract("EffectRight", """
               #{@unit}
                 effect :notify, "Powiadom", handles: :visit_closed, calls: :mail, idempotency: [key: :event_id, owner: :downstream]

                 process_manager :chase, "Pogoń", correlate: :visit_id do
                   starts_on :visit_closed
                   ends_on :visit_closed
                 end
               """)
    end
  end

  describe "P4: a process manager's triggers, timers and commands" do
    test "one that correlates on no field is refused, since every run would share one record" do
      # Found in the review of E11a, beside R2's `correlate []`: the runtime joins no
      # values into one correlation, and the first ending would complete every run.
      message =
        refuse_contract("ManagerUncorrelated", """
        #{@unit}
          process_manager :chase, "Pogoń", correlate: [] do
            starts_on :visit_closed
            ends_on :visit_closed
          end
        """)

      assert message =~
               "P4: process manager :chase correlates on no field, so every run would share one record"
    end

    # Plan DD, C1 (#304): a run's key names each field once, as a process module's
    # does (R2); the doubled field once compiled.
    test "one that correlates on a field twice is refused, naming the field" do
      message =
        refuse_contract("ManagerCorrelatedTwice", """
        #{@unit}
          process_manager :chase, "Pogoń", correlate: [:visit_id, :visit_id] do
            starts_on :visit_closed
            ends_on :visit_closed
          end
        """)

      assert message =~
               "P4: process manager :chase correlates on :visit_id twice; a run's key names each " <>
                 "field once (manager_correlated_twice.ex:12)"
    end

    # Plan N3: a timer says what it is for in the client's words, or does not compile.
    test "a timer without a label is refused" do
      message =
        refuse_contract("TimerUnlabelled", """
        #{@unit}
          process_manager :chase, "Pogoń", correlate: :visit_id do
            starts_on :visit_opened, sets: :later
            timer :later, wait: {1, :day}
          end
        """)

      assert message =~
               "contract -> timer -> later defined in timer_unlabelled.ex:14::\n" <>
                 "  required :label option not found"
    end

    test "what it starts, reacts and ends on, sets, cancels and issues is its own" do
      message =
        refuse_contract("ManagerWrong", """
        #{@unit}
          process_manager :chase, "Pogoń", correlate: :visit_id do
            state do
              field :due_on, :date
            end

            starts_on :visit_opened, sets: :nudge
            on :reminder_due, issues: :call_patient, cancels: :later
            timer :reminder_due, "Reminder due", wait: {1, :day}, at: :due_on, issues: :remind
            timer :deadline, "Deadline", at: :due_on
            timer :idle, "Idle"
            ends_on :visit_forgotten
          end
        """)

      assert message =~
               "P4: process manager :chase starts on :visit_opened, which is neither an event of " <>
                 "this contract, one it consumes, nor a timer of its own (manager_wrong.ex:17)"

      assert message =~ "P4: process manager :chase ends on :visit_forgotten"
      assert message =~ "P4: process manager :chase sets :nudge, which is not a timer of its own"

      assert message =~
               "P4: process manager :chase cancels :later, which is not a timer of its own"

      assert message =~
               "P4: process manager :chase issues :call_patient, which is not a command of this " <>
                 "contract (manager_wrong.ex:18)"

      assert message =~
               "P4: process manager :chase: timer :reminder_due has both wait: and at:; keep one " <>
                 "(manager_wrong.ex:19)"

      assert message =~
               "P4: process manager :chase: timer :deadline fires at :due_on, which is :date, not " <>
                 ":timestamp (manager_wrong.ex:20)"

      assert message =~
               "P4: process manager :chase: timer :idle has neither wait: nor at:; give it exactly " <>
                 "one (manager_wrong.ex:21)"

      refute message =~ "reacts on :reminder_due"
    end

    test "one that starts on nothing is refused" do
      message =
        refuse_contract("ManagerIdle", """
        #{@unit}
          process_manager :chase, "Pogoń", correlate: :visit_id do
            ends_on :visit_closed
          end
        """)

      assert message =~ "P4: process manager :chase starts on no event (manager_idle.ex:12)"
    end

    test "one delivered in the transaction is refused" do
      message =
        refuse_contract("ManagerInline", """
        #{@unit}
          process_manager :chase, "Pogoń", correlate: :visit_id, delivery: :in_transaction do
            starts_on :visit_closed
          end
        """)

      assert message =~
               "P4: process manager :chase is fed from the log in order, after the transaction; " <>
                 "it cannot run :in_transaction (manager_inline.ex:12)"
    end

    test "control: v2 §4.6's shape, with a timer at a timestamp too, compiles" do
      assert %{process_managers: [manager]} =
               compile_contract("ManagerRight", """
               #{@unit}
                 process_manager :chase, "Pogoń" do
                   correlate :visit_id

                   state do
                     field :remind_at, :timestamp
                   end

                   starts_on :visit_closed, sets: [:chase, :at_time]
                   on :chase, issues: :remind, cancels: :at_time
                   timer :chase, "Chase", wait: {24, :hour}, issues: :remind
                   timer :at_time, "At time", at: :remind_at
                   ends_on :reminded
                 end
               """)

      assert [%{name: :chase, wait: %{amount: 24, unit: :hour}}, %{name: :at_time, wait: nil}] =
               manager.timers

      assert manager.ends_on == [:reminded]
    end
  end

  describe "P5: a read model projects known events, and a query reads a local read model" do
    test "an unknown event and an unknown read model are refused" do
      message =
        refuse_contract("ReadWrong", """
        #{@unit}
          read_model :closed_visits, "Zamknięte wizyty", projects: [:visit_closed, :visit_lost] do
            field :closed_on, :date
          end

          query :closed_today, "Zamknięte dziś", reads: :open_visits, by: :reception
        """)

      assert message =~
               "P5: read model :closed_visits projects :visit_lost, which is neither an event of " <>
                 "this contract nor one it consumes (read_wrong.ex:12)"

      assert message =~
               "P5: query :closed_today reads :open_visits, which is not a read model of this " <>
                 "contract (read_wrong.ex:16)"
    end
  end
end
