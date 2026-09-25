defmodule EhOsContract.Next.ContractProcessTest do
  @moduledoc """
  v2 plan, E4: **R1–R6 and K1 of v2 §6** — the one process a contract describes,
  and what it consumes from a sibling. Each refusal names the declaration's file and
  line, and has a control beside it that compiles.
  """

  use EhOsContract.DslCase, async: false

  @unit """
    aggregate :visit, "Wizyta" do
      identity :visit_id
      command :close_visit, "Zamknięcie wizyty", by: :reception, emits: :visit_closed
      event :visit_closed, "Wizyta zamknięta", terminal: true
    end
  """

  describe "R1: exactly one process" do
    test "none is refused at the first declaration" do
      message = refuse_contract("NoProcess", @unit)

      assert message =~
               "R1: a contract describes one process, and this one declares none (no_process.ex:4)"
    end

    test "a second is refused" do
      message =
        refuse_contract("TwoProcesses", """
        #{@unit}
          process :visit, "Wizyta" do
            correlate :visit_id
          end

          process :billing, "Rozliczenie" do
            correlate :visit_id
          end
        """)

      assert message =~
               "R1: a contract describes one process; :billing is a second (two_processes.ex:14)"
    end
  end

  describe "R2: the correlation is in every local event" do
    test "an event without the field is refused, and identity counts as declared" do
      message =
        refuse_contract("Uncorrelated", """
          aggregate :visit, "Wizyta" do
            identity :visit_id
            command :close_visit, "Zamknięcie wizyty", by: :reception, emits: :visit_closed

            event :visit_closed, "Wizyta zamknięta", terminal: true do
              field :clinic_id, :id
            end
          end

          aggregate :invoice, "Faktura" do
            identity :invoice_id
            command :issue_invoice, "Wystawienie", by: :reception, emits: :invoice_issued
            event :invoice_issued, "Wystawiono", terminal: true
          end

          process :visit, "Wizyta" do
            correlate [:visit_id, :clinic_id]
          end
        """)

      assert message =~
               "R2: event :invoice_issued has no field :visit_id, which process :visit correlates " <>
                 "on (uncorrelated.ex:16)"

      assert message =~ "R2: event :invoice_issued has no field :clinic_id"
      refute message =~ "event :visit_closed has no field"
    end
  end

  describe "R3: stages are all or nothing" do
    test "with stages: an ungrouped event, an unknown group and an unplaced include" do
      message =
        refuse_contract("StagesPartly", """
          consumes Clinic.Contracts.Scheduling, :visit_completed

          aggregate :visit, "Wizyta" do
            identity :visit_id
            command :close_visit, "Zamknięcie wizyty", by: :reception, emits: [:visit_closed, :visit_billed]
            event :visit_closed, "Wizyta zamknięta", terminal: true

            stage :billing do
              event :visit_billed, "Rozliczono"
            end
          end

          process :visit, "Wizyta" do
            correlate :visit_id
            stage :closing
            include :visit_completed
          end
        """)

      assert message =~
               "R3: process :visit declares stages, so event :visit_closed has to sit in a stage " <>
                 "group of aggregate :visit (stages_partly.ex:9)"

      assert message =~
               "R3: aggregate :visit groups events into stage :billing, which process :visit does " <>
                 "not declare (stages_partly.ex:11)"

      assert message =~
               "R3: process :visit declares stages, so include :visit_completed has to sit in one " <>
                 "of them (stages_partly.ex:19)"
    end

    test "without stages: a group is refused" do
      message =
        refuse_contract("StagesNone", """
          aggregate :visit, "Wizyta" do
            identity :visit_id
            command :close_visit, "Zamknięcie wizyty", by: :reception, emits: :visit_closed

            stage :closing do
              event :visit_closed, "Wizyta zamknięta", terminal: true
            end
          end

          process :visit, "Wizyta" do
            correlate :visit_id
          end
        """)

      assert message =~
               "R3: process :visit declares no stages, so aggregate :visit cannot group events " <>
                 "into stage :closing (stages_none.ex:8)"
    end

    test "control: every event grouped and every include placed compiles, in stage order" do
      model =
        compile_contract("StagesAll", """
          consumes Clinic.Contracts.Scheduling, :visit_completed

          aggregate :visit, "Wizyta" do
            identity :visit_id
            command :close_visit, "Zamknięcie wizyty", by: :reception, emits: :visit_closed

            stage :closing do
              event :visit_closed, "Wizyta zamknięta", terminal: true
            end
          end

          process :visit, "Wizyta" do
            correlate :visit_id

            stage :departure, "Wyjście" do
              include :visit_completed
            end

            stage :closing
          end
        """)

      assert Enum.map(model.process.stages, & &1.name) == [:departure, :closing]

      assert model.process.includes == [
               %{event: :visit_completed, terminal: false, stage: :departure}
             ]
    end
  end

  describe "R4: include places consumed events" do
    test "a local event, and one nobody declares, are refused" do
      message =
        refuse_contract("IncludeLocal", """
        #{@unit}
          process :visit, "Wizyta" do
            correlate :visit_id
            include :visit_closed
            include :visit_invented
          end
        """)

      assert message =~
               "R4: process :visit includes :visit_closed, but a local event is placed by its " <>
                 "unit's stage group (include_local.ex:12)"

      assert message =~
               "R4: process :visit includes :visit_invented, but it is not an event this contract " <>
                 "consumes (include_local.ex:13)"
    end
  end

  describe "R4 and A4: an event received from another application is not in this log (D12)" do
    test "neither a run nor a boundary can take it in" do
      message =
        refuse_contract("ReceivedInLog", """
          consumes "rehmed.visit.closed.v1", as: :visit_closed_elsewhere do
            field :visit_id, :id
          end

          dcb :payer_period, "Okres płatnika" do
            identity :visit_id
            consults :visit_closed_elsewhere, match: :visit_id
            command :close_period, "Zamknięcie okresu", by: :manager, emits: :period_closed
            event :period_closed, "Zamknięto okres", terminal: true
          end

          process :visit, "Wizyta" do
            correlate :visit_id
            include :visit_closed_elsewhere
          end
        """)

      assert message =~
               "R4: process :visit includes :visit_closed_elsewhere, but it arrives from another " <>
                 "application into an inbox, not into this log (D12); a run across applications is " <>
                 "assembled by EHOS (received_in_log.ex:17)"

      assert message =~
               "A4: dcb :payer_period consults :visit_closed_elsewhere, which arrives from another " <>
                 "application into an inbox, not into this log (D12), so no append condition can " <>
                 "read it (received_in_log.ex:10)"
    end
  end

  describe "R5: a promise is about events of the run" do
    test "an event outside the run is refused, in each position" do
      message =
        refuse_contract("PromiseOutside", """
          consumes Clinic.Contracts.Scheduling, [:visit_completed, :visit_cancelled]

        #{@unit}
          process :visit, "Wizyta" do
            correlate :visit_id
            include :visit_completed

            promise :closed_after_departure do
              from :visit_completed
              eventually :visit_invoiced
              or_else :visit_cancelled
            end
          end
        """)

      assert message =~
               "R5: promise :closed_after_departure: eventually :visit_invoiced is not an event of " <>
                 "the run of process :visit (promise_outside.ex:16)"

      assert message =~ "R5: promise :closed_after_departure: or_else :visit_cancelled"
      refute message =~ "from :visit_completed"
    end
  end

  describe "R6: durations" do
    test "calendar units, negative counts and malformed ones are refused where time is computed" do
      message =
        refuse_contract("Durations", """
        #{@unit}
          process_manager :chase, "Pogoń", correlate: :visit_id do
            starts_on :visit_closed, sets: :reminder
            timer :reminder, wait: {-1, :hour}
            ends_on :visit_closed
          end

          process :visit, "Wizyta" do
            correlate :visit_id
            deadline {1, :month}
            cadence {1, :fortnight}

            promise :closed_quickly do
              from :visit_closed
              eventually :visit_closed
              within 24
            end
          end
        """)

      assert message =~
               "R6: timer :reminder: wait counts -1, which is not a non-negative integer (durations.ex:12)"

      assert message =~
               "R6: process :visit: deadline is in :month, a calendar unit, which only cadence may " <>
                 "use (durations.ex:18)"

      assert message =~ "R6: process :visit: cadence is in :fortnight, which is not one of"
      assert message =~ "R6: promise :closed_quickly: within is 24, which is not {count, unit}"
    end

    test "control: a monthly cadence, a zero window and fixed units compile" do
      model =
        compile_contract("DurationsRight", """
        #{@unit}
          process :visit, "Wizyta" do
            correlate :visit_id
            cadence {1, :month}, unverified: true
            deadline {30, :day}

            promise :closed_at_once do
              from :visit_closed
              eventually :visit_closed
              within {0, :second}
            end
          end
        """)

      assert model.process.cadence == %{amount: 1, unit: :month, unverified: true}
      assert model.process.deadline == %{amount: 30, unit: :day, unverified: false}
      assert [%{within: %{amount: 0, unit: :second}}] = model.process.promises
    end
  end

  describe "K1: consuming a sibling's events" do
    test "itself, nothing, a rename of what it does not consume, and an atom as: are refused" do
      message =
        refuse_contract("ConsumesWrong", """
          consumes EhOsContract.Next.Fixtures.ConsumesWrong, :visit_closed
          consumes Clinic.Contracts.Scheduling, []
          consumes Clinic.Contracts.Booking, :visit_booked, as: [visit_moved: :moved]
          consumes Clinic.Contracts.Reporting, :report_sent, as: :sent

        #{@unit}
          process :visit, "Wizyta" do
            correlate :visit_id
          end
        """)

      assert message =~
               "K1: a contract cannot consume its own events: consumes " <>
                 "EhOsContract.Next.Fixtures.ConsumesWrong (consumes_wrong.ex:4)"

      assert message =~
               "K1: consumes Clinic.Contracts.Scheduling names no events (consumes_wrong.ex:5)"

      assert message =~
               "K1: consumes Clinic.Contracts.Booking renames :visit_moved, which it does not consume"

      assert message =~
               "a sibling's events are renamed with as: [old: :new] (consumes_wrong.ex:7)"
    end

    test "control: a renamed consumed event is known here by its new name" do
      model =
        compile_contract("ConsumesRenamed", """
          consumes Clinic.Contracts.Scheduling, :visit_completed, as: [visit_completed: :patient_left]

        #{@unit}
          process :visit, "Wizyta" do
            correlate :visit_id
            include :patient_left
          end
        """)

      assert [%{kind: :contract, from: Clinic.Contracts.Scheduling, renames: renames}] =
               model.consumes

      assert renames == %{visit_completed: :patient_left}
      assert Map.has_key?(model.digests, "consumes:patient_left")
    end
  end
end
