defmodule EhOsContract.ContractUnitsTest do
  @moduledoc """
  v2 plan, E4: **A1–A5 and C1 of v2 §6** — what a unit decides, and who can ask it
  to. Each refusal names the declaration's file and line, and has a control beside
  it that compiles.
  """

  use EhOsContract.DslCase, async: false

  @process """
    process :visit, "Wizyta" do
      correlate :visit_id
    end
  """

  describe "A1: a command emits events of its own unit" do
    test "nothing, or another unit's event, is refused" do
      message =
        refuse_contract("EmitsWrong", """
          aggregate :visit, "Wizyta" do
            identity :visit_id
            command :close_visit, "Zamknięcie wizyty", by: :reception, emits: []
            command :bill_visit, "Rozliczenie", by: :reception, emits: [:visit_closed, :invoice_issued]
            event :visit_closed, "Wizyta zamknięta", terminal: true
          end

          aggregate :invoice, "Faktura" do
            identity :visit_id
            command :issue_invoice, "Wystawienie", by: :reception, emits: :invoice_issued
            event :invoice_issued, "Wystawiono", terminal: true
          end

        #{@process}
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
          aggregate :visit, "Wizyta" do
            identity :visit_id
            command :close_visit, "Zamknięcie wizyty", by: :reception, emits: :visit_closed
            event :visit_closed, "Wizyta zamknięta", terminal: true
            event :visit_forgotten, "Zapomniano", terminal: true
          end

        #{@process}
        """)

      assert message =~
               "A2: event :visit_forgotten is emitted by no command of aggregate :visit and declares " <>
                 "no recorded_by:, so it could never occur (never_occurs.ex:8)"
    end

    test "control: an event recorded rather than decided compiles (D6)" do
      assert %{grants: %{specialist: %{records: [:visit_completed]}}} =
               compile_contract("Recorded", """
                 aggregate :visit, "Wizyta" do
                   identity :visit_id
                   command :close_visit, "Zamknięcie wizyty", by: :reception, emits: :visit_closed
                   event :visit_closed, "Wizyta zamknięta", terminal: true
                   event :visit_completed, "Pacjent wyszedł z gabinetu", recorded_by: :specialist
                 end

               #{@process}
               """)
    end
  end

  describe "A3: a command rejects its own unit's invariants" do
    test "an invariant the unit does not declare is refused" do
      message =
        refuse_contract("RejectsWrong", """
          aggregate :visit, "Wizyta" do
            identity :visit_id
            invariant :paid, "Zapłacono"

            command :close_visit, "Zamknięcie wizyty",
              by: :reception,
              emits: :visit_closed,
              rejects: [:paid, :booked]

            event :visit_closed, "Wizyta zamknięta", terminal: true
          end

        #{@process}
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
          dcb :payer_period, "Okres płatnika" do
            identity :visit_id
            command :close_period, "Zamknięcie okresu", by: :manager, emits: :period_closed
            event :period_closed, "Zamknięto okres", terminal: true
          end

        #{@process}
        """)

      assert message =~
               "A4: dcb :payer_period consults no event, so it decides over nothing (consults_nothing.ex:4)"
    end

    test "an unknown event, no criterion, and a match outside the identity are refused" do
      message =
        refuse_contract("ConsultsWrong", """
          dcb :payer_period, "Okres płatnika" do
            identity [:visit_id, :period_id]
            consults :visit_invoiced
            consults :visit_settled, match: [:period_id, :payer_id]
            consults :period_closed, match: :period_id
            command :close_period, "Zamknięcie okresu", by: :manager, emits: :period_closed
            event :period_closed, "Zamknięto okres", terminal: true
          end

          process :visit, "Wizyta" do
            correlate [:visit_id, :period_id]
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

    test "a match on a field the local event does not carry as a required :id is refused" do
      # An appended event is tagged with its required, non-personal :id fields, and
      # a boundary finds what it consults by tags: matched on a text field, it would
      # read nothing and the invariant would hold vacuously.
      message = refuse_contract("ConsultsUntagged", consulting_visit_marked(":string"))

      assert message =~
               "A4: dcb :payer_period consults :visit_marked matching :period_id, which the " <>
                 "event does not carry as a required, non-personal :id field, so no appended " <>
                 ":visit_marked is tagged with it and the boundary could never find one " <>
                 "(consults_untagged.ex:17)"

      refute message =~ "matching :payer_id"
    end

    test "control: the same match on required :id fields compiles" do
      assert %{units: [_visit, %{consults: [%{match: [:payer_id, :period_id]}]}]} =
               compile_contract("ConsultsTagged", consulting_visit_marked(":id"))
    end

    test "control: consulting a consumed event, by prose, compiles" do
      assert %{units: [%{consults: [%{event: :visit_completed, where: "wykonana wizyta"}]}]} =
               compile_contract("ConsultsConsumed", """
                 consumes Clinic.Contracts.Scheduling, :visit_completed

                 dcb :payer_period, "Okres płatnika" do
                   identity :visit_id
                   consults :visit_completed, where: "wykonana wizyta"
                   command :close_period, "Zamknięcie okresu", by: :manager, emits: :period_closed
                   event :period_closed, "Zamknięto okres", terminal: true
                 end

               #{@process}
               """)
    end
  end

  describe "A5: state at most once" do
    test "a second state block is refused, in a unit and in a process manager" do
      message =
        refuse_contract("StateTwice", """
          aggregate :visit, "Wizyta" do
            identity :visit_id

            state do
              field :paid, :integer, default: 0
            end

            state do
              field :due, :integer, default: 0
            end

            command :close_visit, "Zamknięcie wizyty", by: :reception, emits: :visit_closed
            event :visit_closed, "Wizyta zamknięta", terminal: true
          end

          process_manager :chase, "Pogoń", correlate: :visit_id do
            state do
            end

            state do
            end

            starts_on :visit_closed
            ends_on :visit_closed
          end

        #{@process}
        """)

      assert message =~ "A5: aggregate :visit declares its state twice (state_twice.ex:11)"
      assert message =~ "A5: process manager :chase declares its state twice (state_twice.ex:23)"
    end
  end

  describe "A6: a generated identity, and the command that creates it" do
    test "two identity fields, no creating command, and creates: without a generated identity" do
      message =
        refuse_contract("GeneratedWrong", """
          aggregate :booking, "Rezerwacja" do
            identity [:clinic_id, :booking_id], generated: :uuid
            command :cancel, "Odwołanie", by: :reception, emits: :cancelled
            event :cancelled, "Odwołano", terminal: true
          end

          aggregate :visit, "Wizyta" do
            identity :visit_id
            command :open_visit, "Otwarcie", by: :reception, emits: :opened, creates: true
            event :opened, "Otwarto"
          end

          process :booking, "Rezerwacja" do
            correlate :clinic_id
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
               dcb :seat, "Miejsce" do
                 identity :seat_id
                 consults :seat_taken, match: :seat_id
                 command :take_seat, "Zajęcie", by: :reception, emits: :seat_taken, creates: true
                 event :seat_taken, "Zajęto"
               end

               process :seat, "Miejsce" do
                 correlate :seat_id
               end
             """) =~
               "A6: command :take_seat creates: dcb :seat, whose identity is not generated; a " <>
                 "boundary's identity comes from its commands, so creates: belongs only to an " <>
                 "aggregate's (generated_on_boundary.ex:7)"
    end

    test "identity with another option than generated: is refused at the declaration" do
      source =
        contract("GeneratedTypo", """
          aggregate :booking, "Rezerwacja" do
            identity :booking_id, generate: :uuid
            command :book, "Rezerwacja", by: :reception, emits: :booked, creates: true
            event :booked, "Zarezerwowano"
          end

          process :booking, "Rezerwacja" do
            correlate :booking_id
          end
        """)

      assert_refused(
        source,
        "generated_typo.ex",
        "identity takes one option beside its fields, `generated: :uuid`, and got [generate: :uuid]",
        5
      )
    end

    test "control: a generated identity with a creating command compiles into the model" do
      model =
        compile_contract("GeneratedRight", """
          aggregate :booking, "Rezerwacja" do
            identity :booking_id, generated: :uuid

            command :book_visit, "Umów wizytę", by: :reception, emits: :visit_booked, creates: true do
              field :slot, :timestamp
            end

            command :cancel, "Odwołanie", by: :reception, emits: :cancelled

            event :visit_booked, "Zarezerwowano" do
              field :slot, :timestamp
            end

            event :cancelled, "Odwołano", terminal: true
          end

          process :booking, "Rezerwacja" do
            correlate :booking_id
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

  describe "C1: a command can be issued" do
    test "a command without by:, which no reaction issues, is refused" do
      message =
        refuse_contract("Unreachable", """
          aggregate :visit, "Wizyta" do
            identity :visit_id
            command :close_visit, "Zamknięcie wizyty", emits: :visit_closed
            event :visit_closed, "Wizyta zamknięta", terminal: true
          end

        #{@process}
        """)

      assert message =~
               "C1: command :close_visit can be issued by no one: give it by:, or have a policy or " <>
                 "a process manager of this contract issue it (unreachable.ex:6)"
    end

    test "control: a command only a policy issues compiles" do
      assert %{commands: [_, %{name: :issue_invoice, by: []}]} =
               compile_contract("IssuedByPolicy", """
                 aggregate :visit, "Wizyta" do
                   identity :visit_id
                   command :close_visit, "Zamknięcie wizyty", by: :reception, emits: :visit_closed
                   command :issue_invoice, "Wystawienie faktury", emits: :invoice_issued
                   event :visit_closed, "Wizyta zamknięta", terminal: true
                   event :invoice_issued, "Wystawiono fakturę", terminal: true
                 end

                 policy :invoice_on_close, "Faktura po zamknięciu",
                   handles: :visit_closed,
                   issues: :issue_invoice

               #{@process}
               """)
    end
  end

  # A visit marked for a payer's period, and the boundary that consults it on both
  # fields; `type` is what the visit's event declares its period as.
  defp consulting_visit_marked(type) do
    """
      aggregate :visit, "Wizyta" do
        identity :visit_id
        command :mark_visit, "Oznaczenie wizyty", by: :manager, emits: :visit_marked do
          field :payer_id, :id
          field :period_id, #{type}
        end
        event :visit_marked, "Oznaczono wizytę" do
          field :payer_id, :id
          field :period_id, #{type}
        end
      end
      dcb :payer_period, "Okres płatnika" do
        identity [:payer_id, :period_id]
        consults :visit_marked, match: [:payer_id, :period_id]
        command :close_period, "Zamknięcie okresu", by: :manager, emits: :period_closed
        event :period_closed, "Zamknięto okres", terminal: true
      end

      process :payer, "Płatnik" do
        correlate :payer_id
      end
    """
  end
end
