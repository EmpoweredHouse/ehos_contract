defmodule EhOsContract.ContractLifecycleTest do
  @moduledoc """
  Plan LC1 (#99): **T1–T4** — an aggregate's lifecycle, its statuses and the events
  that move it between them, and the commands it lets in. Each refusal names the
  declaration's file and line, and has a control beside it that compiles.
  """

  use EhOsContract.DslCase, async: false

  # A visit is booked, the patient arrives, the visit closes; a booked visit can be
  # cancelled, and a visit can be moved back to booked before the patient arrives.
  @visit """
    aggregate :visit, "Visit" do
      identity :visit_id

      invariant :only_a_booked_visit, "Only a booked visit"
      invariant :only_an_open_visit, "Only an open visit"

      lifecycle do
        status :booked, "Booked"
        status :in_progress, "In progress"
        status :closed, "Closed", final: true
        status :cancelled, "Cancelled", final: true

        initial :booked, on: :visit_booked
        transition :booked, :patient_arrived, :in_progress
        transition :booked, :visit_cancelled, :cancelled
        transition :in_progress, :visit_closed, :closed
      end

      command :book_visit, "Booking", by: :reception, emits: :visit_booked

      command :admit_patient, "Admission", by: :reception, emits: :patient_arrived,
        from: [:booked, :booked], or_rejects: :only_a_booked_visit, rejects: :only_a_booked_visit

      command :cancel_visit, "Cancellation", by: :reception, emits: :visit_cancelled,
        from: :booked, or_rejects: :only_a_booked_visit, rejects: :only_a_booked_visit

      command :close_visit, "Closing", by: :reception, emits: [:visit_closed, :note_added],
        from: :in_progress, or_rejects: :only_an_open_visit, rejects: :only_an_open_visit

      command :add_note, "Note", by: :reception, emits: :note_added

      event :visit_booked, "Visit booked"
      event :patient_arrived, "Patient arrived"
      event :note_added, "Note added"
      event :visit_cancelled, "Visit cancelled"
      event :visit_closed, "Visit closed"
    end

    scenario "a visit the patient came to is not admitted again" do
      given :visit_booked
      given :patient_arrived
      command :admit_patient
      rejected :only_a_booked_visit
    end

    scenario "a visit the patient has not come to is not closed" do
      given :visit_booked
      command :close_visit
      rejected :only_an_open_visit
    end
  """

  describe "control" do
    test "a lifecycle compiles into the unit's model, one transition per status it leaves" do
      model = compile_contract("LifecycleRight", @visit)

      assert [%{lifecycle: lifecycle}] = model.units

      assert Enum.map(lifecycle.statuses, &{&1.name, &1.label, &1.final}) == [
               {:booked, "Booked", false},
               {:in_progress, "In progress", false},
               {:closed, "Closed", true},
               {:cancelled, "Cancelled", true}
             ]

      assert lifecycle.initial == [%{status: :booked, on: :visit_booked, source: nil}]

      assert Enum.map(lifecycle.transitions, &{&1.from, &1.event, &1.to}) == [
               {:booked, :patient_arrived, :in_progress},
               {:booked, :visit_cancelled, :cancelled},
               {:in_progress, :visit_closed, :closed}
             ]

      admit = Enum.find(model.commands, &(&1.name == :admit_patient))
      book = Enum.find(model.commands, &(&1.name == :book_visit))

      assert %{from: [:booked], or_rejects: :only_a_booked_visit} = admit
      refute Map.has_key?(book, :from)
      refute Map.has_key?(book, :or_rejects)

      # Plan LC2: the state holds the status, which the model's state does not list.
      state = Module.concat([model.module, Aggregates, Visit, State])
      assert Map.has_key?(struct(state), :status)
      refute Enum.any?(hd(model.units).state.fields, &(&1.name == :status))
    end

    test "a transition from several statuses is one per status in the model" do
      model =
        compile_contract("LifecycleSeveral", """
          aggregate :visit, "Visit" do
            identity :visit_id

            lifecycle do
              status :booked, "Booked"
              status :moved, "Moved"
              status :cancelled, "Cancelled", final: true

              initial :booked, on: :visit_booked
              transition :booked, :visit_moved, :moved
              transition :moved, :visit_moved, :moved
              transition [:booked, :moved, :booked], :visit_cancelled, :cancelled
            end

            command :book_visit, "Booking", by: :reception, emits: :visit_booked
            command :move_visit, "Moving", by: :reception, emits: :visit_moved
            command :cancel_visit, "Cancellation", by: :reception, emits: :visit_cancelled

            event :visit_booked, "Visit booked"
            event :visit_moved, "Visit moved"
            event :visit_cancelled, "Visit cancelled"
          end
        """)

      [%{lifecycle: %{transitions: transitions}}] = model.units

      assert {:booked, :visit_cancelled, :cancelled} in Enum.map(
               transitions,
               &{&1.from, &1.event, &1.to}
             )

      assert Enum.count(transitions, &(&1.event == :visit_cancelled)) == 2

      assert {:moved, :visit_cancelled, :cancelled} in Enum.map(
               transitions,
               &{&1.from, &1.event, &1.to}
             )
    end

    test "a unit without a lifecycle has no lifecycle key, so its digest does not move" do
      model =
        compile_contract("LifecycleNone", """
          aggregate :visit, "Visit" do
            identity :visit_id
            command :close_visit, "Closing", by: :reception, emits: :visit_closed
            event :visit_closed, "Visit closed"
          end
        """)

      assert [unit] = model.units
      refute Map.has_key?(unit, :lifecycle)
    end

    test "a lifecycle moves its aggregate's digest, and the contract's version" do
      without =
        compile_contract("LifecycleDigestWithout", """
          aggregate :visit, "Visit" do
            identity :visit_id
            command :close_visit, "Closing", by: :reception, emits: :visit_closed
            event :visit_closed, "Visit closed"
          end
        """)

      with_lifecycle =
        compile_contract("LifecycleDigestWith", """
          aggregate :visit, "Visit" do
            identity :visit_id

            lifecycle do
              status :closed, "Closed", final: true
              initial :closed, on: :visit_closed
            end

            command :close_visit, "Closing", by: :reception, emits: :visit_closed
            event :visit_closed, "Visit closed"
          end
        """)

      refute without.digests["unit:visit"] == with_lifecycle.digests["unit:visit"]
      refute without.version == with_lifecycle.version
    end
  end

  describe "T1: the lifecycle's shape" do
    test "twice, empty, a status twice or not snake_case is refused" do
      message =
        refuse_contract("LifecycleShape", """
          aggregate :visit, "Visit" do
            identity :visit_id

            lifecycle do
              status :booked, "Booked"
              status :booked, "Booked"
              status :Closed, "Closed", final: true
              initial :booked, on: :visit_booked
              transition :booked, :visit_closed, :Closed
            end

            lifecycle do
            end

            command :book_visit, "Booking", by: :reception, emits: :visit_booked
            command :close_visit, "Closing", by: :reception, emits: :visit_closed
            event :visit_booked, "Visit booked"
            event :visit_closed, "Visit closed"
          end

          aggregate :room, "Room" do
            identity :visit_id

            state do
              field :status, :string
            end

            lifecycle do
            end

            command :open_room, "Opening", by: :reception, emits: :room_opened
            event :room_opened, "Opened"
          end
        """)

      assert message =~
               "T1: aggregate :visit declares lifecycle twice; one holds all its statuses " <>
                 "(lifecycle_shape.ex:15)"

      assert message =~
               "T1: status :Closed of aggregate :visit is not snake_case (lifecycle_shape.ex:10)"

      assert message =~
               "T1: status :booked of aggregate :visit is declared twice (lifecycle_shape.ex:9)"

      assert message =~ "T1: the lifecycle of aggregate :room has no status"

      assert message =~
               "T1: aggregate :room declares a state field :status, which its lifecycle's " <>
                 "status takes; drop it, or rename it"

      assert message =~
               "T1: the lifecycle of aggregate :room has no initial, so no aggregate would ever " <>
                 "have a status; write `initial :status, on: :event`"
    end

    test "a lifecycle on a boundary is not a word of the boundary (L1)" do
      source =
        contract("LifecycleBoundary", """
          dcb :seat, "Seat" do
            identity :seat_id
            consults :seat_taken, match: :seat_id

            lifecycle do
              status :taken, "Taken", final: true
              initial :taken, on: :seat_taken
            end

            command :take_seat, "Taking", by: :reception, emits: :seat_taken
            event :seat_taken, "Seat taken"
          end
        """)

      log =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          assert_raise CompileError, fn -> compile(source, "lifecycle_boundary.ex") end
        end)

      assert log =~ "undefined function lifecycle/1"
    end
  end

  describe "T2: what initial and transition name" do
    test "an unknown status or event, an event starting twice and a pair moving twice are refused" do
      message =
        refuse_contract("LifecycleNames", """
          aggregate :visit, "Visit" do
            identity :visit_id

            lifecycle do
              status :booked, "Booked"
              status :closed, "Closed", final: true

              initial :booked, on: :visit_booked
              initial :closed, on: :visit_booked
              initial :bookd, on: :visit_bookd
              initial :bookd, on: :visit_bookd
              transition :booked, :visit_closed, :closed
              transition :booked, :visit_closed, :booked
              transition :open, :visit_closed, :closed
              transition [], :visit_booked, :closed
            end

            command :book_visit, "Booking", by: :reception, emits: :visit_booked
            command :close_visit, "Closing", by: :reception, emits: :visit_closed
            event :visit_booked, "Visit booked"
            event :visit_closed, "Visit closed"
          end
        """)

      assert message =~
               "T2: initial :bookd names status :bookd, which the lifecycle of aggregate :visit " <>
                 "does not declare; did you mean :booked? (lifecycle_names.ex:13)"

      assert message =~
               "T2: initial :bookd names :visit_bookd, which is not an event of aggregate " <>
                 ":visit; did you mean :visit_booked?"

      assert message =~
               "T2: transition [:open] --visit_closed--> :closed names status :open, which the " <>
                 "lifecycle of aggregate :visit does not declare (lifecycle_names.ex:17)"

      assert message =~
               "T2: transition [] --visit_booked--> :closed leaves no status; name the statuses " <>
                 "it moves out of (lifecycle_names.ex:18)"

      assert message =~
               "T2: initial :bookd on :visit_bookd of aggregate :visit is declared twice"

      refute message =~ "T2: event :visit_bookd starts"

      assert message =~
               "T2: event :visit_booked starts aggregate :visit in two statuses; an initial " <>
                 "event starts it in one (lifecycle_names.ex:12)"

      assert message =~
               "T2: event :visit_closed moves aggregate :visit out of :booked twice; one status " <>
                 "and one event lead to one status (lifecycle_names.ex:16)"
    end
  end

  describe "T3: every status is reached, and only a final one has no way out" do
    test "an unreached status, a final one left and a dead end are refused" do
      message =
        refuse_contract("LifecycleReach", """
          aggregate :visit, "Visit" do
            identity :visit_id

            lifecycle do
              status :booked, "Booked"
              status :waiting, "Waiting"
              status :archived, "Archived"
              status :closed, "Closed", final: true
              status :cancelled_once, "Cancelled", final: true

              initial :booked, on: :visit_booked
              transition :booked, :visit_closed, :closed
              transition :closed, :visit_booked, :booked
              transition :archived, :visit_closed, :closed
              transition :booked, :note_added, :waiting
              transition :waiting, :note_added, :waiting
              transition :cancelled_once, :note_added, :cancelled_once
              transition :booked, :visit_cancelled, :cancelled_once
            end

            command :book_visit, "Booking", by: :reception, emits: :visit_booked
            command :close_visit, "Closing", by: :reception, emits: :visit_closed
            command :add_note, "Note", by: :reception, emits: :note_added
            command :cancel_visit, "Cancellation", by: :reception, emits: :visit_cancelled
            event :visit_booked, "Visit booked"
            event :note_added, "Note added"
            event :visit_cancelled, "Visit cancelled"
            event :visit_closed, "Visit closed"
          end
        """)

      assert message =~
               "T3: status :archived of aggregate :visit is reached from no initial status, so " <>
                 "no aggregate could ever be in it (lifecycle_reach.ex:10)"

      assert message =~
               "T3: status :closed of aggregate :visit is final, and a transition leaves it " <>
                 "(lifecycle_reach.ex:11)"

      assert message =~
               "T3: status :waiting of aggregate :visit has no transition out; mark it " <>
                 "final: true if the aggregate's life ends there (lifecycle_reach.ex:9)"

      # A transition back into the same status is no way out, and no way out of a terminal one.
      refute message =~ "T3: status :cancelled_once"
    end
  end

  describe "T4: a command's from: and or_rejects:" do
    test "each way from: or or_rejects: can be wrong is refused" do
      message =
        refuse_contract("LifecycleFrom", """
          aggregate :visit, "Visit" do
            identity :visit_id, generated: :uuid

            invariant :only_a_booked_visit, "Only a booked visit"

            lifecycle do
              status :booked, "Booked"
              status :in_progress, "In progress"
              status :closed, "Closed", final: true

              initial :booked, on: :visit_booked
              transition :booked, :patient_arrived, :in_progress
              transition :in_progress, :visit_closed, :closed
            end

            command :book_visit, "Booking", by: :reception, emits: :visit_booked,
              creates: true, from: :booked, or_rejects: :only_a_booked_visit,
              rejects: :only_a_booked_visit

            command :admit_patient, "Admission", by: :reception, emits: :patient_arrived,
              from: :boked

            command :close_visit, "Closing", by: :reception, emits: :visit_closed,
              from: :booked, or_rejects: :closed_once, rejects: :only_a_booked_visit

            command :reopen_visit, "Opening", by: :reception, emits: :patient_arrived,
              from: [:in_progress, :closed], or_rejects: :only_a_booked_visit

            command :readmit, "Readmission", by: :reception, emits: :patient_arrived,
              from: [:booked, :in_progress], or_rejects: :only_a_booked_visit,
              rejects: :only_a_booked_visit

            command :remind, "Reminder", by: :reception, emits: :patient_arrived,
              or_rejects: :only_a_booked_visit, rejects: :only_a_booked_visit

            event :visit_booked, "Visit booked"
            event :patient_arrived, "Patient arrived"
            event :visit_closed, "Visit closed"
          end

          aggregate :room, "Room" do
            identity :visit_id
            invariant :free_room, "A free room"

            command :open_room, "Opening", by: :reception, emits: :room_opened,
              from: :free, or_rejects: :free_room, rejects: :free_room

            event :room_opened, "Opened"
          end
        """)

      assert message =~
               "T4: command :book_visit creates: its aggregate, which has no status before it, " <>
                 "so it has no from:"

      assert message =~
               "T4: command :admit_patient is issued from status :boked, which the lifecycle of " <>
                 "aggregate :visit does not declare; did you mean :booked?"

      assert message =~
               "T4: command :admit_patient has from: without or_rejects:; name the invariant it " <>
                 "is refused on in any other status"

      assert message =~
               "T4: command :close_visit or_rejects: :closed_once, which is not an invariant of " <>
                 "its unit"

      assert message =~
               "T4: command :close_visit emits :visit_closed, and no transition moves aggregate " <>
                 ":visit with it out of [:booked]"

      assert message =~
               "T4: command :reopen_visit is issued from :closed, which is final: nothing is " <>
                 "decided once the aggregate's life has ended"

      assert message =~
               "T4: command :reopen_visit or_rejects: :only_a_booked_visit, which is not in its " <>
                 "rejects:; add it there"

      # Issued in a status none of its events leaves, with no rule but or_rejects: to
      # refuse on there: the decision could only raise (plan LC4a).
      assert message =~
               "T4: command :readmit is issued from :in_progress, which no event it emits " <>
                 "leaves, and rejects: names no rule but its or_rejects: to refuse on there"

      refute message =~ "T4: command :readmit is issued from :booked"

      assert message =~
               "T4: command :remind has or_rejects: without from:; name the statuses it may be " <>
                 "issued in"

      assert message =~
               "T4: command :open_room has from:, and aggregate :room declares no lifecycle"
    end

    # Plan DD, A1 (#247): the engine refuses on an `actor_is` invariant itself, so it is
    # no rule the decision can refuse on in a status it cannot leave.
    test "an actor_is invariant is no rule to refuse on in a stuck status" do
      message =
        refuse_contract("LifecycleStuckPerson", """
          aggregate :visit, "Visit" do
            identity :visit_id, generated: :uuid

            state do
              field :specialist_id, :id, optional: true
            end

            invariant :only_a_booked_visit, "Only a booked visit"
            invariant :own_visit, "Only one's own visit"

            lifecycle do
              status :booked, "Booked"
              status :in_progress, "In progress"

              initial :booked, on: :visit_booked
              transition :booked, :patient_arrived, :in_progress
            end

            command :book_visit, "Booking", by: :reception, emits: :visit_booked, creates: true

            command :readmit, "Readmission", by: :reception, emits: :patient_arrived,
              from: [:booked, :in_progress], or_rejects: :only_a_booked_visit,
              rejects: [:only_a_booked_visit, :own_visit] do
              actor_is :specialist_id, or_rejects: :own_visit
            end
          end
        """)

      assert message =~
               "T4: command :readmit is issued from :in_progress, which no event it emits " <>
                 "leaves, and rejects: names no rule but its or_rejects: to refuse on there"
    end

    test "from: is no word of a boundary's command (L1)" do
      message =
        refuse_contract("LifecycleFromBoundary", """
          dcb :seat, "Seat" do
            identity :seat_id
            consults :seat_taken, match: :seat_id
            invariant :free_seat, "A free seat"

            command :take_seat, "Taking", by: :reception, emits: :seat_taken,
              from: :free, rejects: :free_seat

            event :seat_taken, "Seat taken"
          end
        """)

      assert message =~ "unknown options [:from]"
      refute message =~ "T4:"
    end

    test "a creating command that emits no initial event is refused" do
      assert refuse_contract("LifecycleCreates", """
               aggregate :visit, "Visit" do
                 identity :visit_id, generated: :uuid

                 lifecycle do
                   status :booked, "Booked", final: true
                   initial :booked, on: :visit_booked
                 end

                 command :book_visit, "Booking", by: :reception, emits: :visit_booked
                 command :draft_visit, "Draft", by: :reception, emits: :drafted, creates: true

                 event :visit_booked, "Visit booked"
                 event :drafted, "Draft"
               end
             """) =~
               "T4: command :draft_visit creates: its aggregate, and emits none of its " <>
                 "lifecycle's initial events, so the aggregate it makes would have no status " <>
                 "(lifecycle_creates.ex:"
    end

    test "control: a status no event leaves compiles when the decision has a rule to refuse on there" do
      model =
        compile_contract("LifecycleFiner", """
          aggregate :visit, "Visit" do
            identity :visit_id

            invariant :only_a_booked_visit, "Only a booked visit"
            invariant :not_while_paid, "Not once paid"

            lifecycle do
              status :booked, "Booked"
              status :paid, "Paid"
              status :closed, "Closed", final: true

              initial :booked, on: :visit_booked
              transition :booked, :visit_paid, :paid
              transition :booked, :visit_closed, :closed
              transition :paid, :visit_closed, :closed
            end

            command :book_visit, "Booking", by: :reception, emits: :visit_booked
            command :close_visit, "Closing", by: :reception, emits: :visit_closed

            command :pay_visit, "Payment", by: :reception, emits: :visit_paid,
              from: [:booked, :paid], or_rejects: :only_a_booked_visit,
              rejects: [:only_a_booked_visit, :not_while_paid]

            event :visit_booked, "Visit booked"
            event :visit_paid, "Visit paid"
            event :visit_closed, "Visit closed"
          end

          scenario "a closed visit is not paid" do
            given :visit_booked
            given :visit_closed
            command :pay_visit
            rejected :only_a_booked_visit
          end

          scenario "a paid visit is not paid again" do
            given :visit_booked
            given :visit_paid
            command :pay_visit
            rejected :not_while_paid
          end
        """)

      assert %{from: [:booked, :paid]} = Enum.find(model.commands, &(&1.name == :pay_visit))
    end
  end
end
