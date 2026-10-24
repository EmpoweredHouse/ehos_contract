defmodule EhOsContract.ContractUnitsTest do
  @moduledoc """
  v2 plan, E4: **A1–A5 and C1 of v2 §6** — what a unit decides, and who can ask it
  to. Each refusal names the declaration's file and line, and has a control beside
  it that compiles.
  """

  use EhOsContract.DslCase, async: false

  describe "A1: a command emits events of its own unit" do
    test "nothing, or another unit's event, is refused" do
      message =
        refuse_contract("EmitsWrong", """
          aggregate :visit, "Visit" do
            identity :visit_id
            command :close_visit, "Closing the visit", by: :reception, emits: []
            command :bill_visit, "Bill", by: :reception, emits: [:visit_closed, :invoice_issued]
            event :visit_closed, "Visit closed"
          end

          aggregate :invoice, "Invoice" do
            identity :visit_id
            command :issue_invoice, "Issuing", by: :reception, emits: :invoice_issued
            event :invoice_issued, "Issued"
          end
        """)

      assert message =~
               "A1: command :close_visit emits nothing; name the events it may produce (emits_wrong.ex:6)"

      assert message =~
               "A1: command :bill_visit emits :invoice_issued, which is not an event of aggregate " <>
                 ":visit (emits_wrong.ex:7)"
    end
  end

  describe "A2: every event can occur" do
    test "an event no command emits and nobody records is refused" do
      message =
        refuse_contract("NeverOccurs", """
          aggregate :visit, "Visit" do
            identity :visit_id
            command :close_visit, "Closing the visit", by: :reception, emits: :visit_closed
            event :visit_closed, "Visit closed"
            event :visit_forgotten, "Forgotten"
          end
        """)

      assert message =~
               "A2: event :visit_forgotten is emitted by no command of aggregate :visit and declares " <>
                 "no recorded_by:, so it could never occur (never_occurs.ex:8)"
    end

    test "control: an event recorded rather than decided compiles (D6)" do
      assert %{grants: %{specialist: %{records: [:visit_completed]}}} =
               compile_contract("Recorded", """
                 aggregate :visit, "Visit" do
                   identity :visit_id
                   command :close_visit, "Closing the visit", by: :reception, emits: :visit_closed
                   event :visit_closed, "Visit closed"
                   event :visit_completed, "The patient left the room", recorded_by: :specialist
                 end
               """)
    end
  end

  describe "A3: a command rejects its own unit's invariants" do
    test "an invariant the unit does not declare is refused" do
      message =
        refuse_contract("RejectsWrong", """
          aggregate :visit, "Visit" do
            identity :visit_id
            invariant :paid, "Paid"

            command :close_visit, "Closing the visit",
              by: :reception,
              emits: :visit_closed,
              rejects: [:paid, :booked]

            event :visit_closed, "Visit closed"
          end
        """)

      assert message =~
               "A3: command :close_visit rejects :booked, which is neither an invariant of " <>
                 "aggregate :visit nor a constraint of the command (rejects_wrong.ex:8)"

      refute message =~ "rejects :paid"
    end
  end

  describe "A4: a dynamic consistency boundary consults what it decides over" do
    test "consulting nothing is refused" do
      message =
        refuse_contract("ConsultsNothing", """
          dcb :payer_period, "Payer's period" do
            identity :visit_id
            command :close_period, "Closing the period", by: :manager, emits: :period_closed
            event :period_closed, "Period closed"
          end
        """)

      assert message =~
               "A4: dcb :payer_period consults no event, so it decides over nothing (consults_nothing.ex:4)"
    end

    test "an unknown event, no criterion, and a match outside the identity are refused" do
      message =
        refuse_contract("ConsultsWrong", """
          dcb :payer_period, "Payer's period" do
            identity [:visit_id, :period_id]
            consults :visit_invoiced
            consults :visit_settled, match: [:period_id, :payer_id]
            consults :period_closed, match: :period_id
            command :close_period, "Closing the period", by: :manager, emits: :period_closed
            event :period_closed, "Period closed"
          end
        """)

      assert message =~
               "A4: dcb :payer_period consults :visit_invoiced, which is neither an event of this " <>
                 "contract nor one it consumes (consults_wrong.ex:6)"

      assert message =~
               "A4: dcb :payer_period consults :visit_invoiced with neither match: nor where: " <>
                 "(consults_wrong.ex:6)"

      assert message =~
               "A4: dcb :payer_period consults :visit_settled matching :payer_id, which is not in " <>
                 "its identity [:visit_id, :period_id] (consults_wrong.ex:7)"

      refute message =~ "consults :period_closed"
    end

    # Plan DD, C1 (#304): a match is the key the boundary reads by, and names each field
    # once, as a process manager's and a process module's correlate do.
    test "a match naming a field twice is refused, naming the field" do
      message =
        refuse_contract("ConsultsMatchTwice", """
          dcb :payer_period, "Payer's period" do
            identity :period_id
            consults :period_closed, match: [:period_id, :period_id]
            command :close_period, "Closing the period", by: :manager, emits: :period_closed
            event :period_closed, "Period closed"
          end
        """)

      assert message =~
               "A4: dcb :payer_period consults :period_closed matching :period_id twice; a match " <>
                 "names each field once (consults_match_twice.ex:6)"
    end

    test "a wrong field named twice in a match is reported once" do
      message =
        refuse_contract("ConsultsWrongTwice", """
          dcb :payer_period, "Payer's period" do
            identity :period_id
            consults :period_closed, match: [:payer_id, :payer_id]
            command :close_period, "Closing the period", by: :manager, emits: :period_closed
            event :period_closed, "Period closed"
          end
        """)

      assert message =~ "matching :payer_id twice"

      assert length(String.split(message, "matching :payer_id, which is not in its identity")) ==
               2,
             message
    end

    test "a match on a field the local event does not carry as a required :id is refused" do
      # An appended event is tagged with its required, non-personal :id fields, and
      # a boundary finds what it consults by tags: matched on a text field, it would
      # read nothing and the invariant would hold vacuously.
      message = refuse_contract("ConsultsUntagged", consulting_visit_marked(":string"))

      assert message =~
               "A4: dcb :payer_period consults :visit_marked matching :period_id, which the " <>
                 "event does not carry as a required, non-personal :id field, or one of a " <>
                 "domain value, so no appended :visit_marked is tagged with it and the " <>
                 "boundary could never find one (consults_untagged.ex:17)"

      refute message =~ "matching :payer_id"
    end

    test "control: the same match on required :id fields compiles" do
      assert %{units: [_visit, %{consults: [%{match: [:payer_id, :period_id]}]}]} =
               compile_contract("ConsultsTagged", consulting_visit_marked(":id"))
    end

    # #435: a field of a domain value tags an appended event when the value rests on
    # :id, which only the domain can say; the rules between modules hold it to that.
    test "control: a match on a field of a domain value compiles, for the domain to judge" do
      assert %{units: [_visit, %{consults: [%{match: [:payer_id, :period_id]}]}]} =
               compile_contract("ConsultsValue", consulting_visit_marked(":period"))
    end

    test "control: consulting a consumed event, by prose, compiles" do
      assert %{
               units: [
                 %{consults: [%{event: :visit_completed, where: "a visit that took place"}]}
               ]
             } =
               compile_contract("ConsultsConsumed", """
                 consumes Clinic.Contracts.Scheduling, :visit_completed

                 dcb :payer_period, "Payer's period" do
                   identity :visit_id
                   consults :visit_completed, where: "a visit that took place"
                   command :close_period, "Closing the period", by: :manager, emits: :period_closed
                   event :period_closed, "Period closed"
                 end
               """)
    end
  end

  describe "A5: state at most once" do
    test "a second state block is refused, in a unit and in a process manager" do
      message =
        refuse_contract("StateTwice", """
          aggregate :visit, "Visit" do
            identity :visit_id

            state do
              field :paid, :integer, default: 0
            end

            state do
              field :due, :integer, default: 0
            end

            command :close_visit, "Closing the visit", by: :reception, emits: :visit_closed
            event :visit_closed, "Visit closed"
          end

          process_manager :chase, "Chase", correlate: :visit_id do
            state do
            end

            state do
            end

            starts_on :visit_closed
            ends_on :visit_closed
          end
        """)

      assert message =~ "A5: aggregate :visit declares its state twice (state_twice.ex:11)"
      assert message =~ "A5: process manager :chase declares its state twice (state_twice.ex:23)"
    end
  end

  describe "A6: a generated identity, and the command that creates it" do
    test "two identity fields, no creating command, and creates: without a generated identity" do
      message =
        refuse_contract("GeneratedWrong", """
          aggregate :booking, "Booking" do
            identity [:clinic_id, :booking_id], generated: :uuid
            command :cancel, "Cancellation", by: :reception, emits: :cancelled
            event :cancelled, "Cancelled"
          end

          aggregate :visit, "Visit" do
            identity :visit_id
            command :open_visit, "Opening", by: :reception, emits: :opened, creates: true
            event :opened, "Opened"
          end
        """)

      assert message =~
               "A6: aggregate :booking is identified by [:clinic_id, :booking_id]; a generated " <>
                 "identity is one field (generated_wrong.ex:4)"

      assert message =~
               "A6: aggregate :booking has a generated identity and no command that creates: it"

      assert message =~
               "A6: command :open_visit creates: aggregate :visit, whose identity is not " <>
                 "generated; write `identity :visit_id, generated: :uuid` (generated_wrong.ex:12)"
    end

    test "creates: on a boundary's command says a boundary has no generated identity" do
      assert refuse_contract("GeneratedOnBoundary", """
               dcb :seat, "Seat" do
                 identity :seat_id
                 consults :seat_taken, match: :seat_id
                 command :take_seat, "Taking", by: :reception, emits: :seat_taken, creates: true
                 event :seat_taken, "Taken"
               end
             """) =~
               "A6: command :take_seat creates: dcb :seat, whose identity is not generated; a " <>
                 "boundary's identity comes from its commands, so creates: belongs only to an " <>
                 "aggregate's (generated_on_boundary.ex:7)"
    end

    test "identity with another option than generated: is refused at the declaration" do
      source =
        contract("GeneratedTypo", """
          aggregate :booking, "Booking" do
            identity :booking_id, generate: :uuid
            command :book, "Booking", by: :reception, emits: :booked, creates: true
            event :booked, "Reserved"
          end
        """)

      assert_refused(
        source,
        "generated_typo.ex",
        "identity takes one option beside its fields, `generated: :uuid`, and got [generate: :uuid]",
        5
      )
    end

    # Plan DD, L3 (#286): a typed identity is a keyword, never a second argument.
    test "an identity typed as a second argument is refused, naming the form that types it" do
      source =
        contract("IdentityPositional", """
          aggregate :visit_note, "Note" do
            identity :visit_id, {:id, :visit}
            command :note, "Write down", by: :reception, emits: :noted
            event :noted, "Written down"
          end
        """)

      assert_refused(
        source,
        "identity_positional.ex",
        "and got {:id, :visit}; a field of it typed as another unit's or an entity's number, " <>
          "or by a domain value, is written in the list of its fields: " <>
          "`identity visit_id: {:id, :visit}`",
        5
      )
    end

    test "control: a generated identity with a creating command compiles into the model" do
      model =
        compile_contract("GeneratedRight", """
          aggregate :booking, "Booking" do
            identity :booking_id, generated: :uuid

            command :book_visit, "Book a visit", by: :reception, emits: :visit_booked, creates: true do
              field :slot, :timestamp
            end

            command :cancel, "Cancellation", by: :reception, emits: :cancelled

            event :visit_booked, "Reserved" do
              field :slot, :timestamp
            end

            event :cancelled, "Cancelled"
          end
        """)

      assert [%{identity: [:booking_id], generated: :uuid}] = model.units

      book = Enum.find(model.commands, &(&1.name == :book_visit))
      cancel = Enum.find(model.commands, &(&1.name == :cancel))

      assert book.creates
      assert %{name: :booking_id, optional: true} = hd(book.fields)
      refute Map.has_key?(cancel, :creates)
      assert %{name: :booking_id, optional: false} = hd(cancel.fields)
    end
  end

  describe "A8: a command reads an entity by a field that names one (plan DD, T2a, #240)" do
    test "a field that is missing, optional, an identity or not an entity's is refused" do
      message =
        refuse_contract("ReadsWrong", """
          aggregate :visit, "Visit" do
            identity :visit_id

            command :book_visit, "Book a visit",
              by: :reception,
              emits: :visit_booked,
              reads: [service: :service_id, room: :room_id, card: :card_id, visit: :visit_id,
                      code: :code, again: :service_id, again: :service_id] do
              field :service_id, {:id, :service}
              field :card_id, {:id, :card}, optional: true
              field :code, :id
            end

            event :visit_booked, "Booked"
          end
        """)

      assert message =~
               "A8: command :book_visit reads :room by :room_id, which is not one of its fields " <>
                 "(reads_wrong.ex:7)"

      assert message =~
               "A8: command :book_visit reads :card by :card_id, which it declares optional; " <>
                 "without it there is nothing to read"

      assert message =~
               "A8: command :book_visit reads :visit by :visit_id, a field of the unit's " <>
                 "identity, which names the unit, not a row to read; an entity is read by a " <>
                 "field of the command's own typed {:id, entity}"

      assert message =~
               "A8: command :book_visit reads :code by :code, typed :id; an entity is named by a " <>
                 "field typed {:id, entity}"

      assert message =~ "A8: command :book_visit reads :again twice; give each row its own name"
      refute message =~ "reads :service by"
    end

    test "a command that reads, issued by a policy or a process manager, is refused" do
      message =
        refuse_contract("ReadsByReaction", """
          aggregate :visit, "Visit" do
            identity :visit_id

            command :book_visit, "Book a visit",
              by: :reception,
              emits: :visit_booked,
              reads: [service: :service_id] do
              field :service_id, {:id, :service}
            end

            event :visit_booked, "Booked"
          end

          policy :rebook, "Book again", handles: :visit_booked, issues: :book_visit,
            delivery: :in_transaction

          process_manager :follow_up, "Follow-up visit" do
            correlate :visit_id
            starts_on :visit_booked, issues: :book_visit
          end
        """)

      assert message =~
               "A8: command :book_visit reads entities and is issued by policy :rebook, process " <>
                 "manager :follow_up; a command that reads is issued only by an actor in by:, " <>
                 "since a reaction's would be looked up inside the transaction that reacted"
    end

    test "a process manager's timer issuing a command that reads is refused as well" do
      message =
        refuse_contract("ReadsByTimer", """
          aggregate :visit, "Visit" do
            identity :visit_id

            command :book_visit, "Book a visit",
              by: :reception,
              emits: :visit_booked,
              reads: [service: :service_id] do
              field :service_id, {:id, :service}
            end

            event :visit_booked, "Booked"
          end

          process_manager :follow_up, "Follow-up visit" do
            correlate :visit_id
            starts_on :visit_booked, sets: :again
            timer :again, "In a month", wait: {1, :month}, issues: :book_visit
          end
        """)

      assert message =~
               "A8: command :book_visit reads entities and is issued by process manager :follow_up"
    end

    test "control: a required field typed {:id, entity} compiles, and the model keeps it" do
      model =
        compile_contract("ReadsRight", """
          aggregate :visit, "Visit" do
            identity :visit_id

            command :book_visit, "Book a visit",
              by: :reception,
              emits: :visit_booked,
              reads: [service: :service_id] do
              field :service_id, {:id, :service}
            end

            command :cancel_visit, "Cancel", by: :reception, emits: :visit_cancelled

            event :visit_booked, "Booked"
            event :visit_cancelled, "Cancelled"
          end
        """)

      commands = Map.new(model.commands, &{&1.name, &1})
      assert commands.book_visit.reads == [service: :service_id]
      # Kept only where it is set, so no other command's digest moves.
      refute Map.has_key?(commands.cancel_visit, :reads)
    end
  end

  describe "A9: the person who must issue a command is named by the unit's state (plan DD, A1, #247)" do
    test "a field outside the state, of another type or personal; an invariant outside rejects:; a creating or by-less command; twice" do
      message =
        refuse_contract("ActorIsWrong", """
          aggregate :visit, "Visit" do
            identity :visit_id

            state do
              field :specialist_id, :id, optional: true
              field :room, :string, optional: true
              field :patient_id, :id, personal: :patient, subject: :patient, optional: true
            end

            invariant :own_visit, "Own visit only"

            command :close_a, "A", by: :reception, emits: :closed, rejects: :own_visit do
              actor_is :nurse_id, or_rejects: :own_visit
            end

            command :close_b, "B", by: :reception, emits: :closed, rejects: :own_visit do
              actor_is :room, or_rejects: :own_visit
            end

            command :close_c, "C", by: :reception, emits: :closed, rejects: :own_visit do
              actor_is :patient_id, or_rejects: :own_visit
            end

            command :close_d, "D", by: :reception, emits: :closed do
              actor_is :specialist_id, or_rejects: :own_visit
            end

            command :close_e, "E", emits: :closed, rejects: :own_visit do
              actor_is :specialist_id, or_rejects: :own_visit
            end

            command :close_f, "F", by: :reception, emits: :closed, rejects: :own_visit do
              actor_is :specialist_id, or_rejects: :own_visit
              actor_is :visit_id, or_rejects: :own_visit
            end

            event :closed, "Closed"
          end

          policy :close_on_close, "Close", handles: :closed, issues: :close_e,
            delivery: :in_transaction
        """)

      assert message =~
               "A9: command :close_a, actor_is :nurse_id: is not a field of the unit's state; " <>
                 "the person is one the unit already knows"

      assert message =~
               "A9: command :close_b, actor_is :room: is typed :string; a person is named by an :id"

      assert message =~
               "A9: command :close_c, actor_is :patient_id: is personal; the subject compared " <>
                 "with it would be a person's data in a refusal"

      assert message =~
               "A9: command :close_d, actor_is :specialist_id: or_rejects: :own_visit is not an " <>
                 "invariant of the unit in the command's rejects:"

      assert message =~
               "A9: command :close_e, actor_is :specialist_id: the command names nobody in by:, " <>
                 "so no person issues it"

      assert message =~ "A9: command :close_f names who must issue it twice"

      assert message =~
               "A9: command :close_f, actor_is :visit_id: is the unit's identity, which the " <>
                 "caller fills in the command, so anyone could name themselves"
    end

    test "a command that creates its aggregate names nobody yet" do
      message =
        refuse_contract("ActorIsCreates", """
          aggregate :visit, "Visit" do
            identity :visit_id, generated: :uuid

            state do
              field :specialist_id, :id, optional: true
            end

            invariant :own_visit, "Own visit only"

            command :open_visit, "Open", by: :reception, emits: :opened, creates: true,
              rejects: :own_visit do
              actor_is :specialist_id, or_rejects: :own_visit
            end

            event :opened, "Opened"
          end
        """)

      assert message =~
               "A9: command :open_visit, actor_is :specialist_id: the command creates: its " <>
                 "aggregate, which has no state yet to name anyone"
    end

    test "control: a field of the state or the identity compiles, and the model keeps it" do
      model =
        compile_contract("ActorIsRight", """
          aggregate :visit, "Visit" do
            identity :visit_id

            state do
              field :specialist_id, {:id, :specialist}, optional: true
            end

            invariant :own_visit, "Own visit only"

            command :close_visit, "Close", by: :reception, emits: :closed, rejects: :own_visit do
              actor_is :specialist_id, or_rejects: :own_visit
            end

            command :reopen_visit, "Reopen", by: :reception, emits: :reopened

            event :closed, "Closed"
            event :reopened, "Reopened"
          end

          scenario "someone else closes" do
            actor :reception
            as "specialist-ola"
            command :close_visit
            rejected :own_visit
          end
        """)

      commands = Map.new(model.commands, &{&1.name, &1})
      assert commands.close_visit.actor_is == %{field: :specialist_id, or_rejects: :own_visit}
      refute Map.has_key?(commands.reopen_visit, :actor_is)
    end
  end

  describe "C1: a command can be issued" do
    test "a command without by:, which no reaction issues, is refused" do
      message =
        refuse_contract("Unreachable", """
          aggregate :visit, "Visit" do
            identity :visit_id
            command :close_visit, "Closing the visit", emits: :visit_closed
            event :visit_closed, "Visit closed"
          end
        """)

      assert message =~
               "C1: command :close_visit can be issued by no one: give it by:, or have a policy or " <>
                 "a process manager of this contract issue it (unreachable.ex:6)"
    end

    test "an empty by: is no one either" do
      message =
        refuse_contract("EmptyBy", """
          aggregate :visit, "Visit" do
            identity :visit_id
            command :close_visit, "Closing the visit", by: [], emits: :visit_closed
            event :visit_closed, "Visit closed"
          end
        """)

      assert message =~
               "C1: command :close_visit can be issued by no one: give it by:, or have a policy or " <>
                 "a process manager of this contract issue it (empty_by.ex:6)"
    end

    test "control: a command only a policy issues compiles" do
      assert %{commands: [_, %{name: :issue_invoice, by: []}]} =
               compile_contract("IssuedByPolicy", """
                 aggregate :visit, "Visit" do
                   identity :visit_id
                   command :close_visit, "Closing the visit", by: :reception, emits: :visit_closed
                   command :issue_invoice, "Issuing the invoice", emits: :invoice_issued
                   event :visit_closed, "Visit closed"
                   event :invoice_issued, "Invoice issued"
                 end

                 policy :invoice_on_close, "Invoice after closing",
                   handles: :visit_closed,
                   issues: :issue_invoice
               """)
    end
  end

  # A visit marked for a payer's period, and the boundary that consults it on both
  # fields; `type` is what the visit's event declares its period as.
  defp consulting_visit_marked(type) do
    """
      aggregate :visit, "Visit" do
        identity :visit_id
        command :mark_visit, "Marking the visit", by: :manager, emits: :visit_marked do
          field :payer_id, :id
          field :period_id, #{type}
        end
        event :visit_marked, "Visit marked" do
          field :payer_id, :id
          field :period_id, #{type}
        end
      end
      dcb :payer_period, "Payer's period" do
        identity [:payer_id, :period_id]
        consults :visit_marked, match: [:payer_id, :period_id]
        command :close_period, "Closing the period", by: :manager, emits: :period_closed
        event :period_closed, "Period closed"
      end
    """
  end
end
