defmodule EhOsContract.Next.ContractUnitsTest do
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
      assert %{capabilities: %{specialist: %{records: [:visit_completed]}}} =
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
               "A3: command :close_visit rejects :booked, which is not an invariant of aggregate " <>
                 ":visit (rejects_wrong.ex:8)"

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
end
