defmodule EhosContract.CheckCompletenessContractTest do
  @moduledoc """
  Plan EL1: **ESDM's completeness rules that read one contract** — a unit with no
  event, an event nothing reads, a read model no query asks, a process manager that
  never ends or only waits, an event named after its unit — and the library's own,
  a boundary consulting by prose alone. Each finding points at its declaration, and
  each rule has a control beside it.
  """

  use EhosContract.DslCase, async: false

  alias EhosContract.Check.{Completeness, Finding}

  @visits EhosContract.CheckCompletenessContractTest.Visits
  @slots EhosContract.CheckCompletenessContractTest.Slots

  setup_all do
    compile(
      """
      defmodule #{inspect(@visits)} do
        use EhosContract.Contract, domain: Clinic, context: :settlement, id: "clinic.#{contract_name(@visits)}"

        aggregate :visit, "Visit" do
          identity :visit_id

          command :book, "Book", by: :reception, emits: :booked
          command :note, "Note", by: :reception, emits: :noted
          command :reschedule, "Reschedule", by: :reception, emits: :rescheduled
          command :close, "Close", by: :reception, emits: :visit_closed

          event :booked, "Booked"
          event :noted, "Noted"
          event :rescheduled, "Rescheduled"
          event :visit_closed, "Closed"
        end

        aggregate :drawer, "Drawer" do
          identity :visit_id
        end

        read_model :bookings, "Visits", projects: :booked do
          field :visit_id, :id
        end

        read_model :forgotten, "Forgotten", projects: :booked do
          field :visit_id, :id
        end

        query :bookings_of, "Visits", reads: :bookings, by: :reception do
          param :visit_id, :id
        end

        process_manager :reminder, "Reminder" do
          correlate :visit_id
          starts_on :booked, sets: :remind
          timer :remind, "Remind", wait: {1, :day}
        end

        process_manager :follow_up, "Follow-up" do
          correlate :visit_id
          starts_on :booked
          on :rescheduled
          ends_on :visit_closed
        end
      end

      defmodule #{inspect(@slots)} do
        use EhosContract.Contract, domain: Clinic, context: :settlement, id: "clinic.#{contract_name(@slots)}"

        dcb :slot, "Slot" do
          identity [:room_id, :slot_id]

          consults :taken, match: :room_id
          consults :room_closed, where: "every closed room"

          command :take, "Take", by: :reception, emits: :taken
          event :taken, "Taken"
          event :room_closed, "Room closed", recorded_by: :reception
        end
      end
      """,
      "visits.ex"
    )

    :ok
  end

  defp findings(rule) do
    for %Finding{rule: ^rule} = f <- Completeness.findings([@visits, @slots]),
        do: {f.message, Finding.place(f)}
  end

  test "a unit with no event; control: one with events" do
    assert [{message, {"visits.ex", 18}}] = findings("aggregate-without-events")
    assert message =~ "aggregate :drawer"
  end

  test "an event nothing reads; control: projected, reacted to, ending a manager, consulted" do
    assert [{message, {"visits.ex", 13}}] = findings("event-without-consumer")
    assert message =~ "event :noted of #{inspect(@visits)} has no consumer"
  end

  test "a read model no query reads; control: one a query reads" do
    assert [{message, {"visits.ex", 26}}] = findings("read-model-without-query")
    assert message =~ "read model :forgotten"
  end

  test "a process manager that never ends, and one that only waits; control: one that does both" do
    assert [{never_ends, {"visits.ex", 34}}] = findings("process-manager-without-ends-on")
    assert never_ends =~ "process manager :reminder"

    assert [{only_waits, {"visits.ex", 34}}] = findings("process-manager-without-event-reactions")
    assert only_waits =~ "process manager :reminder"
  end

  test "an event named after its unit; control: the other three" do
    assert [{message, {"visits.ex", 15}}] = findings("event-name-with-aggregate-prefix")
    assert message =~ "event :visit_closed repeats the name of its unit :visit"
  end

  test "a boundary consulting by prose alone; control: one consulting by match" do
    assert [{message, {"visits.ex", 55}}] = findings("consults-without-match")

    assert message =~
             "boundary :slot of #{inspect(@slots)} consults :room_closed with `where:` alone"
  end

  test "a scenario that proves an in-transaction policy fans out; control: one command" do
    compile(
      """
      defmodule EhosContract.CheckCompletenessContractTest.FanOut do
        use EhosContract.Contract, domain: Clinic, context: :settlement, id: "clinic.fan_out"

        aggregate :batch, "Batch" do
          identity :batch_id
          command :start, "Start", by: :reception, emits: :started
          command :handle_item, "Handle", emits: :item_handled
          event :started, "Started"
          event :item_handled, "Handled"
        end

        policy :handle_each, "Handle each", handles: :started, issues: :handle_item
        policy :handle_one, "Handle one", handles: :started, issues: :handle_item

        scenario "two items" do
          target :handle_each
          on :started
          issues :handle_item
          issues :handle_item
        end

        scenario "one item" do
          target :handle_one
          on :started
          issues :handle_item
        end
      end
      """,
      "fan_out.ex"
    )

    module = EhosContract.CheckCompletenessContractTest.FanOut

    assert [%Finding{message: message} = finding] =
             for(
               f <- Completeness.findings([module]),
               f.rule == "in-transaction-policy-fan-out",
               do: f
             )

    assert message =~ "policy :handle_each"
    assert message =~ "scenario \"two items\" shows it issuing 2 commands"
    assert Finding.place(finding) == {"fan_out.ex", 12}
  end

  test "an event read only by ends_on, a process, a publish or a sibling has a consumer" do
    compile(
      """
      defmodule EhosContract.CheckCompletenessContractTest.Intake do
        use EhosContract.Contract, domain: Clinic, context: :settlement, id: "clinic.intake"

        aggregate :referral, "Referral" do
          identity :visit_id

          command :receive, "Receive", by: :reception, emits: :received
          command :withdraw, "Withdraw", by: :reception, emits: :withdrawn
          command :accept, "Accept", by: :reception, emits: :accepted
          command :forward, "Forward", by: :reception, emits: :forwarded
          command :sign, "Sign", by: :reception, emits: :signed

          event :received, "Received"
          event :withdrawn, "Withdrawn"
          event :accepted, "Accepted"
          event :forwarded, "Forwarded"
          event :signed, "Signed"
        end

        process_manager :chase, "Chase" do
          correlate :visit_id
          starts_on :received
          ends_on :withdrawn
        end

        publish :forwarded, from: :forwarded, fields: [:visit_id]
      end

      defmodule EhosContract.CheckCompletenessContractTest.Referral do
        use EhosContract.Process, id: "clinic.referral", domain: Clinic, label: "Referral"

        correlate :visit_id

        stage :acceptance,
          include: [{EhosContract.CheckCompletenessContractTest.Intake, [:received, :accepted]}]
      end

      defmodule EhosContract.CheckCompletenessContractTest.Archive do
        use EhosContract.Contract, domain: Clinic, context: :settlement, id: "clinic.archive"

        consumes EhosContract.CheckCompletenessContractTest.Intake, :signed
      end
      """,
      "intake.ex"
    )

    intake = EhosContract.CheckCompletenessContractTest.Intake
    archive = EhosContract.CheckCompletenessContractTest.Archive
    referral = EhosContract.CheckCompletenessContractTest.Referral

    unread = fn contracts, processes ->
      for f <- Completeness.findings(contracts, processes),
          f.rule == "event-without-consumer",
          do: f.message
    end

    assert unread.([intake, archive], [referral]) == []

    # Control: the sibling is what reads :signed, so without it the event is unread.
    assert [message] = unread.([intake], [referral])
    assert message =~ "event :signed of #{inspect(intake)} has no consumer"

    # Control: the process module is what reads :accepted.
    assert [message] = unread.([intake, archive], [])
    assert message =~ "event :accepted of #{inspect(intake)} has no consumer"
  end

  # Plan DD, P1b (#186): an event a unit's lifecycle starts on or moves on is read by
  # the report's lifecycle section (LC3), process or not, so it has a consumer.
  test "an event a lifecycle starts on or moves on has a consumer" do
    unread =
      for %Finding{rule: "event-without-consumer"} = f <-
            Completeness.findings([LifecycleRig.Visits]),
          do: f.message

    # Not terminal, read by nothing else: only the lifecycle reads them.
    for event <- ~w(booked patient_arrived)a,
        do: refute(Enum.any?(unread, &(&1 =~ "event #{inspect(event)} of")), "#{event} unread")

    # Control: an event of the same unit that no lifecycle moves on is still unread.
    assert Enum.any?(unread, &(&1 =~ "event :note_added of LifecycleRig.Visits has no consumer"))
  end
end
