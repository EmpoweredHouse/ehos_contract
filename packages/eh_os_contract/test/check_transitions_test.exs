defmodule EhOsContract.CheckTransitionsTest do
  @moduledoc """
  Plan DD, S4: **a declared transition no scenario takes** (`transition-without-scenario`),
  a warning at the transition, with one taken beside it: a command's scenario whose
  `given` leaves the unit in the transition's `from`, expecting its event.
  """

  use EhOsContract.DslCase, async: false

  alias EhOsContract.Check.{Completeness, Finding}

  @loans EhOsContract.Fixtures.TransitionLoans

  # The lifecycle's transitions are at lines 17–21 of the file (`contract/2` puts the
  # body at line 4).
  setup_all do
    compile(
      contract("TransitionLoans", """
        aggregate :loan, "Loan" do
          identity :loan_id

          invariant :checked_before_return, "A return is accepted once the equipment is checked"
          invariant :only_a_lent_loan, "Only lent equipment is archived"

          lifecycle do
            status :open, "Open"
            status :lent, "Lent"
            status :closed, "Closed", final: true
            status :archived, "Archived", final: true

            initial :open, on: :opened
            transition :open, :lent, :lent
            transition [:open, :lent], :closed, :closed
            transition :lent, :returned, :open
            transition :lent, :noted, :open
            transition [:open, :lent], :archived, :archived
          end

          command :open_loan, "Open", by: :reception, emits: :opened
          command :lend, "Lend", by: :reception, emits: :lent
          command :close_loan, "Close", by: :reception, emits: :closed

          command :archive_loan, "Archive", by: :reception, emits: :archived, from: :lent,
            or_rejects: :only_a_lent_loan, rejects: :only_a_lent_loan

          command :return_loan, "Return", by: :reception, emits: :returned,
            rejects: :checked_before_return

          event :opened, "Opened"
          event :lent, "Lent"
          event :returned, "Returned"
          event :noted, "Noted", recorded_by: :reception
          event :closed, "Closed"
          event :archived, "Archived"
        end

        scenario "open — lent" do
          given :opened
          command :lend
          expect :lent
        end

        scenario "lent — closed" do
          given :opened
          given :lent
          command :close_loan
          expect :closed
        end

        scenario "lent — archived" do
          given :opened
          given :lent
          command :archive_loan
          expect :archived
        end

        scenario "open — archiving rejected" do
          given :opened
          command :archive_loan
          rejected :only_a_lent_loan
        end

        scenario "lent — return rejected" do
          given :opened
          given :lent
          command :return_loan
          rejected :checked_before_return
        end
      """),
      "transition_loans.ex"
    )

    :ok
  end

  defp findings do
    for %Finding{rule: "transition-without-scenario"} = f <- Completeness.findings([@loans]),
        do: {f.message, Finding.place(f)}
  end

  test "each transition no scenario takes, from the statuses no scenario starts in" do
    assert [{closed, {"transition_loans.ex", 18}}, {returned, {"transition_loans.ex", 19}}] =
             findings()

    # Taken from :lent, not from :open: a transition from two statuses needs both.
    assert closed ==
             "aggregate :loan of #{inspect(@loans)} moves from :open to :closed on :closed, and " <>
               "no scenario of a command starts there and expects it, so nothing shows the " <>
               "implementation takes that transition"

    # A rejected scenario starts in :lent and expects nothing, so it takes nothing.
    assert returned =~ "moves from :lent to :open on :returned"
  end

  test "control: a transition a scenario takes, one on an event only recorded, and a `from` no command admits" do
    messages = Enum.map(findings(), &elem(&1, 0))

    # :archive_loan is issued only `from: :lent`, so no scenario could start in :open.
    refute Enum.any?(messages, &(&1 =~ ":archived"))

    refute Enum.any?(messages, &(&1 =~ "on :lent,"))
    refute Enum.any?(messages, &(&1 =~ "from :lent to :closed"))
    refute Enum.any?(messages, &(&1 =~ ":noted"))
  end

  # Issue #430's review: an event a command emits and an actor also records. Only the
  # command's scenario shows the implementation taking the transition; a recording decides
  # nothing.
  test "a recording of an event a command also emits takes no transition" do
    compile(
      contract("TransitionRecorded", """
        aggregate :ticket, "Ticket" do
          identity :ticket_id

          lifecycle do
            status :open, "Open"
            status :closed, "Closed", final: true

            initial :open, on: :opened
            transition :open, :closed, :closed
          end

          command :open_ticket, "Open", by: :reception, emits: :opened
          command :close_ticket, "Close", by: :reception, emits: :closed

          event :opened, "Opened"
          event :closed, "Closed", recorded_by: :reception
        end

        scenario "a ticket is opened" do
          command :open_ticket
          expect :opened
        end

        scenario "reception notes a ticket closed" do
          actor :reception
          given :opened
          record :closed
          expect :closed
        end
      """),
      "transition_recorded.ex"
    )

    messages =
      for %Finding{rule: "transition-without-scenario"} = f <-
            Completeness.findings([EhOsContract.Fixtures.TransitionRecorded]),
          do: f.message

    assert [message] = messages
    assert message =~ "moves from :open to :closed on :closed"
  end
end
