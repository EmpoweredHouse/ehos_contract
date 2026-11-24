defmodule EhosContract.ContractProcessTest do
  @moduledoc """
  A contract declares no process: what is left of R1–R6 of v2 §6, and K1, what a
  contract consumes from a sibling. A process, its runs, stages, promises and deadline,
  is a module of its own (`EhosContract.Process`, its rules in
  `test/dsl/process_module_test.exs`); plan DD, P2h (#221) took the contract's own form
  away. Each refusal names the declaration's file and line, and has a control beside it
  that compiles.
  """

  use EhosContract.DslCase, async: false

  @bare_unit """
    aggregate :visit, "Visit" do
      identity :visit_id
      command :close_visit, "Closing the visit", by: :reception, emits: :visit_closed
      event :visit_closed, "Visit closed"
    end
  """

  describe "a contract declares no process" do
    test "its model has no process, and its events no stage and no end of a run" do
      model = compile_contract("NoProcess", @bare_unit)

      refute Map.has_key?(model, :process)
      assert EhosContract.Model.process(model) == nil
      assert EhosContract.Model.process_events(model) == []
      assert [%{name: :visit_closed} = event] = model.events
      refute Map.has_key?(event, :stage)
      refute Map.has_key?(event, :terminal)
    end

    test "a `process` in a contract is not a word of it any more" do
      log =
        refused_by_compiler("ProcessGone", """
        #{@bare_unit}
          process :visit, "Visit" do
            correlate :visit_id
          end
        """)

      assert log =~ "undefined function process/3"
    end

    test "nor is a stage group in a unit" do
      log =
        refused_by_compiler("StageGone", """
          aggregate :visit, "Visit" do
            identity :visit_id
            command :close_visit, "Closing the visit", by: :reception, emits: :visit_closed

            stage :closing do
              event :visit_closed, "Visit closed"
            end
          end
        """)

      assert log =~ "undefined function stage/2"
    end

    test "and `terminal:` is not an option of an event" do
      message =
        refuse_contract("TerminalGone", """
          aggregate :visit, "Visit" do
            identity :visit_id
            command :close_visit, "Closing the visit", by: :reception, emits: :visit_closed
            event :visit_closed, "Visit closed", terminal: true
          end
        """)

      assert message =~ "terminal"
    end
  end

  describe "R1: a contract declares something" do
    test "a contract that declares nothing is refused" do
      assert refuse_contract("Empty", "") =~
               "R1: a contract declares what decides in it, or what reacts, and this one " <>
                 "declares nothing"
    end
  end

  describe "A4: an event received from another application is not in this log (D12)" do
    test "a boundary cannot take it in" do
      message =
        refuse_contract("ReceivedInLog", """
          subscribe "scheduling.visit.closed.v1", as: :visit_closed_elsewhere do
            field :visit_id, :id
          end

          dcb :payer_period, "Payer's period" do
            identity :visit_id
            consults :visit_closed_elsewhere, match: :visit_id
            command :close_period, "Closing the period", by: :manager, emits: :period_closed
            event :period_closed, "Period closed"
          end
        """)

      assert message =~
               "A4: dcb :payer_period consults :visit_closed_elsewhere, which arrives from another " <>
                 "application into an inbox, not into this log (D12), so no append condition can " <>
                 "read it (received_in_log.ex:10)"
    end
  end

  describe "R6: a timer's wait" do
    test "a negative count is refused" do
      message =
        refuse_contract("NoProcessTimer", """
          aggregate :visit, "Visit" do
            identity :visit_id
            command :close_visit, "Closing the visit", by: :reception, emits: :visit_closed
            event :visit_closed, "Visit closed"
          end

          process_manager :chase, "Chase", correlate: :visit_id do
            starts_on :visit_closed, sets: :reminder
            timer :reminder, "Reminder", wait: {-1, :hour}
            ends_on :visit_closed
          end
        """)

      assert message =~
               "R6: timer :reminder: wait counts -1, which is not a non-negative integer (no_process_timer.ex:12)"
    end

    test "control: a calendar unit is a timer's to use" do
      model =
        compile_contract("CalendarWait", """
        #{@bare_unit}
          process_manager :chase, "Chase", correlate: :visit_id do
            starts_on :visit_closed, sets: :reminder
            timer :reminder, "Reminder", wait: {1, :month}
            ends_on :visit_closed
          end
        """)

      assert [%{timers: [%{wait: %{amount: 1, unit: :month}}]}] = model.process_managers
    end

    test "a wait longer than 100 years is refused, and the message names the limit" do
      message =
        refuse_contract("CenturyWait", """
        #{@bare_unit}
          process_manager :chase, "Chase", correlate: :visit_id do
            starts_on :visit_closed, sets: :reminder
            timer :reminder, "Reminder", wait: {1201, :month}
            ends_on :visit_closed
          end
        """)

      assert message =~
               "R6: timer :reminder: wait is longer than 100 years, the longest a duration may " <>
                 "be (a year counted as 366 days, a month as a twelfth of that)"
    end

    test "control: a wait of 100 years compiles, in years and in months" do
      for {name, wait} <- [
            {"CenturyWaitKept", "{100, :year}"},
            {"CenturyMonths", "{1200, :month}"}
          ] do
        model =
          compile_contract(name, """
          #{@bare_unit}
            process_manager :chase, "Chase", correlate: :visit_id do
              starts_on :visit_closed, sets: :reminder
              timer :reminder, "Reminder", wait: #{wait}
              ends_on :visit_closed
            end
          """)

        assert [%{timers: [%{wait: %{amount: amount}}]}] = model.process_managers
        assert amount in [100, 1200]
      end
    end
  end

  describe "K1: consuming a sibling's events" do
    test "itself, nothing, a rename of what it does not consume, and an atom as: are refused" do
      message =
        refuse_contract("ConsumesWrong", """
          consumes EhosContract.Fixtures.ConsumesWrong, :visit_closed
          consumes Clinic.Contracts.Scheduling, []
          consumes Clinic.Contracts.Booking, :visit_booked, as: [visit_moved: :moved]
          consumes Clinic.Contracts.Reporting, :report_sent, as: :sent

        #{@bare_unit}
        """)

      assert message =~
               "K1: a contract cannot consume its own events: consumes " <>
                 "EhosContract.Fixtures.ConsumesWrong (consumes_wrong.ex:4)"

      assert message =~
               "K1: consumes Clinic.Contracts.Scheduling names no events (consumes_wrong.ex:5)"

      assert message =~
               "K1: consumes Clinic.Contracts.Booking renames :visit_moved, which it does not consume"

      assert message =~
               "a sibling's events are renamed with as: [old: :new] (consumes_wrong.ex:7)"
    end

    test "fields declared for a sibling's event are refused, not silently dropped" do
      message =
        refuse_contract("ConsumesSiblingFields", """
          consumes Clinic.Contracts.Scheduling, :visit_completed do
            field :visit_id, :id
          end

        #{@bare_unit}
        """)

      assert message =~
               "K1: consumes Clinic.Contracts.Scheduling declares fields; a sibling's event is read " <>
                 "in the shape its own contract declares (v2 §7), never copied " <>
                 "(consumes_sibling_fields.ex:4)"
    end

    test "control: a renamed consumed event is known here by its new name" do
      model =
        compile_contract("ConsumesRenamed", """
          consumes Clinic.Contracts.Scheduling, :visit_completed, as: [visit_completed: :patient_left]

        #{@bare_unit}
          policy :follow_up, "Check-up", handles: :patient_left, issues: :close_visit
        """)

      assert [%{kind: :contract, from: Clinic.Contracts.Scheduling, renames: renames}] =
               model.consumes

      assert renames == %{visit_completed: :patient_left}
      assert Map.has_key?(model.digests, "consumes:patient_left")
    end
  end

  # What the compiler logs for a word the DSL does not have: an undefined function,
  # before the `CompileError` that names no cause.
  defp refused_by_compiler(name, body) do
    ExUnit.CaptureIO.capture_io(:stderr, fn ->
      assert_raise CompileError, fn ->
        compile(contract(name, body), "#{Macro.underscore(name)}.ex")
      end
    end)
  end
end
