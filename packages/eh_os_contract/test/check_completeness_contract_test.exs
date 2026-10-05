defmodule EhOsContract.CheckCompletenessContractTest do
  @moduledoc """
  Plan EL1: **ESDM's completeness rules that read one contract** — a unit with no
  event, an event nothing reads, a read model no query asks, a process manager that
  never ends or only waits, an event named after its unit — and the library's own,
  a boundary consulting by prose alone. Each finding points at its declaration, and
  each rule has a control beside it.
  """

  use EhOsContract.DslCase, async: false

  alias EhOsContract.Check.{Completeness, Finding}

  @visits EhOsContract.CheckCompletenessContractTest.Visits
  @slots EhOsContract.CheckCompletenessContractTest.Slots

  setup_all do
    compile(
      """
      defmodule #{inspect(@visits)} do
        use EhOsContract.Contract, domain: Clinic, context: :settlement

        aggregate :visit, "Wizyta" do
          identity :visit_id

          command :book, "Umów", by: :reception, emits: :booked
          command :note, "Notatka", by: :reception, emits: :noted
          command :reschedule, "Przełóż", by: :reception, emits: :rescheduled
          command :close, "Zamknij", by: :reception, emits: :visit_closed

          event :booked, "Umówiono"
          event :noted, "Zanotowano"
          event :rescheduled, "Przełożono"
          event :visit_closed, "Zamknięto", terminal: true
        end

        aggregate :drawer, "Szuflada" do
          identity :visit_id
        end

        read_model :bookings, "Wizyty", projects: :booked do
          field :visit_id, :id
        end

        read_model :forgotten, "Zapomniane", projects: :booked do
          field :visit_id, :id
        end

        query :bookings_of, "Wizyty", reads: :bookings, by: :reception do
          param :visit_id, :id
        end

        process_manager :reminder, "Przypomnienie" do
          correlate :visit_id
          starts_on :booked, sets: :remind
          timer :remind, "Remind", wait: {1, :day}
        end

        process_manager :follow_up, "Kontrola" do
          correlate :visit_id
          starts_on :booked
          on :rescheduled
          ends_on :visit_closed
        end

        process :visit, "Wizyta" do
          correlate :visit_id
        end
      end

      defmodule #{inspect(@slots)} do
        use EhOsContract.Contract, domain: Clinic, context: :settlement

        dcb :slot, "Termin" do
          identity [:room_id, :slot_id]

          consults :taken, match: :room_id
          consults :room_closed, where: "każdy zamknięty gabinet"

          command :take, "Zajmij", by: :reception, emits: :taken
          event :taken, "Zajęto"
          event :room_closed, "Zamknięto gabinet", recorded_by: :reception
        end

        process :slot, "Termin" do
          correlate :room_id
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

  test "an event nothing reads; control: projected, reacted to, ending a run, consulted" do
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
    assert [{message, {"visits.ex", 59}}] = findings("consults-without-match")

    assert message =~
             "boundary :slot of #{inspect(@slots)} consults :room_closed with `where:` alone"
  end

  test "a scenario that proves an in-transaction policy fans out; control: one command" do
    compile(
      """
      defmodule EhOsContract.CheckCompletenessContractTest.FanOut do
        use EhOsContract.Contract, domain: Clinic, context: :settlement

        aggregate :batch, "Paczka" do
          identity :batch_id
          command :start, "Rozpocznij", by: :reception, emits: :started
          command :handle_item, "Obsłuż", emits: :item_handled
          event :started, "Rozpoczęto"
          event :item_handled, "Obsłużono"
        end

        policy :handle_each, "Obsłuż każdy", handles: :started, issues: :handle_item
        policy :handle_one, "Obsłuż jeden", handles: :started, issues: :handle_item

        process :batch, "Paczka" do
          correlate :batch_id
        end

        scenario "dwa elementy" do
          target :handle_each
          on :started
          issues :handle_item
          issues :handle_item
        end

        scenario "jeden element" do
          target :handle_one
          on :started
          issues :handle_item
        end
      end
      """,
      "fan_out.ex"
    )

    module = EhOsContract.CheckCompletenessContractTest.FanOut

    assert [%Finding{message: message} = finding] =
             for(
               f <- Completeness.findings([module]),
               f.rule == "in-transaction-policy-fan-out",
               do: f
             )

    assert message =~ "policy :handle_each"
    assert message =~ "scenario \"dwa elementy\" shows it issuing 2 commands"
    assert Finding.place(finding) == {"fan_out.ex", 12}
  end

  test "an event read only by ends_on, a promise, a publish or a sibling has a consumer" do
    compile(
      """
      defmodule EhOsContract.CheckCompletenessContractTest.Intake do
        use EhOsContract.Contract, domain: Clinic, context: :settlement

        aggregate :referral, "Skierowanie" do
          identity :visit_id

          command :receive, "Przyjmij", by: :reception, emits: :received
          command :withdraw, "Wycofaj", by: :reception, emits: :withdrawn
          command :accept, "Zaakceptuj", by: :reception, emits: :accepted
          command :forward, "Przekaż", by: :reception, emits: :forwarded
          command :sign, "Podpisz", by: :reception, emits: :signed

          event :received, "Przyjęto"
          event :withdrawn, "Wycofano"
          event :accepted, "Zaakceptowano"
          event :forwarded, "Przekazano"
          event :signed, "Podpisano"
        end

        process_manager :chase, "Ponaglenie" do
          correlate :visit_id
          starts_on :received
          ends_on :withdrawn
        end

        publish :forwarded, as: "clinic.referral.forwarded.v1", from: :forwarded, fields: [:visit_id]

        process :referral, "Skierowanie" do
          correlate :visit_id

          promise :accepted_in_time do
            from :received
            eventually :accepted
            within {2, :day}
          end
        end
      end

      defmodule EhOsContract.CheckCompletenessContractTest.Archive do
        use EhOsContract.Contract, domain: Clinic, context: :settlement

        consumes EhOsContract.CheckCompletenessContractTest.Intake, :signed

        process :archive, "Archiwum" do
          correlate :visit_id
        end
      end
      """,
      "intake.ex"
    )

    intake = EhOsContract.CheckCompletenessContractTest.Intake
    archive = EhOsContract.CheckCompletenessContractTest.Archive

    unread = fn contracts ->
      for f <- Completeness.findings(contracts), f.rule == "event-without-consumer", do: f.message
    end

    assert unread.([intake, archive]) == []

    # Control: the sibling is what reads :signed, so without it the event is unread.
    assert [message] = unread.([intake])
    assert message =~ "event :signed of #{inspect(intake)} has no consumer"
  end
end
