defmodule EhOsContract.ContractConsumersTest do
  @moduledoc """
  v2 plan, E4: **P1–P5 of v2 §6**, and P6 (#472) — what reacts to events, and what is read. Each
  refusal names the declaration's file and line, and has a control beside it that
  compiles.
  """

  use EhOsContract.DslCase, async: false

  @unit """
    aggregate :visit, "Visit" do
      identity :visit_id
      command :close_visit, "Closing a visit", by: :reception, emits: :visit_closed
      command :remind, "Reminder", by: :reception, emits: :reminded
      event :visit_closed, "Visit closed"
      event :reminded, "Reminded"
    end
  """

  describe "P1: a policy handles known events and issues local commands" do
    test "an unknown event and a foreign command are refused" do
      message =
        refuse_contract("PolicyWrong", """
        #{@unit}
          policy :remind_on_close, "Remind after closing",
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
          policy :remind_on_nothing, "Remind for no reason", handles: [], issues: :remind
        """)

      assert message =~
               "P1: policy :remind_on_nothing handles no event, so it never runs; name the events " <>
                 "it reacts to (policy_handles_nothing.ex:12)"
    end

    test "an effect that handles no event is refused" do
      message =
        refuse_contract("EffectHandlesNothing", """
        #{@unit}
          effect :notify_nobody, "Notify for no reason", handles: [], delivery: :in_transaction
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
                 policy :remind_on_booking, "Remind after booking",
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
          effect :notify, "Notify", handles: :visit_closed, calls: :mail, delivery: :in_transaction
          effect :notify_again, "Notify again", handles: :visit_closed, calls: :mail

          policy :remind_later, "Remind later",
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
                 effect :notify, "Notify", handles: :visit_closed, calls: :mail, idempotency: [key: :event_id, owner: :downstream]

                 process_manager :chase, "Chase", correlate: :visit_id do
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
          process_manager :chase, "Chase", correlate: [] do
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
          process_manager :chase, "Chase", correlate: [:visit_id, :visit_id] do
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
          process_manager :chase, "Chase", correlate: :visit_id do
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
          process_manager :chase, "Chase", correlate: :visit_id do
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
          process_manager :chase, "Chase", correlate: :visit_id do
            ends_on :visit_closed
          end
        """)

      assert message =~ "P4: process manager :chase starts on no event (manager_idle.ex:12)"
    end

    test "one delivered in the transaction is refused" do
      message =
        refuse_contract("ManagerInline", """
        #{@unit}
          process_manager :chase, "Chase", correlate: :visit_id, delivery: :in_transaction do
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
                 process_manager :chase, "Chase" do
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
          read_model :closed_visits, "Closed visits", projects: [:visit_closed, :visit_lost] do
            field :closed_on, :date
          end

          query :closed_today, "Closed today", reads: :open_visits, by: :reception
        """)

      assert message =~
               "P5: read model :closed_visits projects :visit_lost, which is neither an event of " <>
                 "this contract nor one it consumes (read_wrong.ex:12)"

      assert message =~
               "P5: query :closed_today reads :open_visits, which is not a read model of this " <>
                 "contract (read_wrong.ex:16)"
    end
  end

  describe "P6: a read model with a table names its key, and only one with a table does" do
    test "a table and its key compile, and are kept in the model" do
      model =
        compile_contract("TableKey", """
        #{@unit}
          read_model :closed_visits, "Closed visits", projects: :visit_closed,
            table: "clinic_closed_visits", key: [:visit_id, :closed_on] do
            field :visit_id, :id
            field :closed_on, :date
            field :note, :string, optional: true
          end
        """)

      [read_model] = model.read_models
      assert read_model.table == "clinic_closed_visits"
      assert read_model.key == [:visit_id, :closed_on]
    end

    # Kept out of the model where undeclared, so a read model written without them keeps
    # its digest, and its subscription is not marked stale by an upgrade.
    test "a read model without a table hashes as it did before tables existed" do
      body = """
      #{@unit}
        read_model :closed_visits, "Closed visits", projects: :visit_closed do
          field :visit_id, :id
        end
      """

      model = compile_contract("TableNone", body)
      [read_model] = model.read_models
      refute Map.has_key?(read_model, :table)
      refute Map.has_key?(read_model, :key)
    end

    test "a table without a key, and a key without a table" do
      message =
        refuse_contract("TableWithoutKey", """
        #{@unit}
          read_model :closed_visits, "Closed visits", projects: :visit_closed,
            table: "clinic_closed_visits" do
            field :visit_id, :id
          end

          read_model :open_visits, "Open visits", projects: :visit_closed, key: :visit_id do
            field :visit_id, :id
          end
        """)

      assert message =~
               "P6: read model :closed_visits keeps its rows in table \"clinic_closed_visits\" and " <>
                 "declares no key:; name the row fields that make a row unique"

      assert message =~
               "P6: read model :open_visits declares key: [:visit_id] and no table:; a key is the " <>
                 "primary key of the table its rows are kept in"
    end

    test "a key field unknown, named twice, optional, personal or a list" do
      message =
        refuse_contract("KeyUnfit", """
        #{@unit}
          read_model :closed_visits, "Closed visits", projects: :visit_closed,
            table: "clinic_closed_visits",
            key: [:visit_id, :visit_id, :missing, :note, :patient_name, :tags] do
            field :visit_id, :id
            field :patient_id, :id, subject: :patient
            field :note, :string, optional: true
            field :patient_name, :string, personal: :patient_id
            field :tags, {:list, :string}
          end
        """)

      where = "P6: read model :closed_visits"
      assert message =~ "#{where} names :visit_id twice in its key"
      assert message =~ "#{where} has :missing in its key, which is not a field of its row"
      assert message =~ "#{where} has :note in its key, which is optional; every row has its key"

      assert message =~
               "#{where} has :patient_name in its key, which is personal; an erasure would leave " <>
                 "rows no key tells apart"

      assert message =~ "#{where} has :tags in its key, which is a list; a key field is one value"
      refute message =~ "has :visit_id in its key"
    end

    test "a table that is no SQL name, and two read models in one table" do
      message =
        refuse_contract("TableShared", """
        #{@unit}
          read_model :closed_visits, "Closed visits", projects: :visit_closed,
            table: "visits", key: :visit_id do
            field :visit_id, :id
          end

          read_model :open_visits, "Open visits", projects: :visit_closed,
            table: "visits", key: :visit_id do
            field :visit_id, :id
          end

          read_model :all_visits, "All visits", projects: :visit_closed,
            table: "public.visits", key: :visit_id do
            field :visit_id, :id
          end
        """)

      assert message =~
               "P6: read model :open_visits keeps its rows in table \"visits\", as read model " <>
                 ":closed_visits does; each read model has a table of its own"

      assert message =~
               "P6: read model :all_visits keeps its rows in table \"public.visits\", which is not " <>
                 "a table name: letters, digits and _, not starting with a digit"

      refute message =~ "read model :closed_visits keeps its rows"
    end

    test "a table longer than Postgres keeps, or the engine's own" do
      long = String.duplicate("a", 64)

      message =
        refuse_contract("TableReserved", """
        #{@unit}
          read_model :closed_visits, "Closed visits", projects: :visit_closed,
            table: "#{long}", key: :visit_id do
            field :visit_id, :id
          end

          read_model :open_visits, "Open visits", projects: :visit_closed,
            table: "eh_os_contract_events", key: :visit_id do
            field :visit_id, :id
          end

          read_model :all_visits, "All visits", projects: :visit_closed,
            table: "oban_jobs", key: :visit_id do
            field :visit_id, :id
          end

          read_model :sixty_three, "Sixty-three", projects: :visit_closed,
            table: "#{String.duplicate("b", 63)}", key: :visit_id do
            field :visit_id, :id
          end
        """)

      assert message =~
               "P6: read model :closed_visits keeps its rows in table \"#{long}\", " <>
                 "longer than the 63 bytes Postgres keeps of a name"

      assert message =~
               "P6: read model :open_visits keeps its rows in table \"eh_os_contract_events\", " <>
                 "which is the engine's or Oban's; a read model's reset/0 would delete its rows"

      assert message =~ "P6: read model :all_visits keeps its rows in table \"oban_jobs\", which"
      refute message =~ "read model :sixty_three"
    end
  end
end
