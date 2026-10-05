defmodule EhOsContract.CheckTransitionsTest do
  @moduledoc """
  Plan DD, S4: **a declared transition no scenario takes** (`transition-without-scenario`),
  a warning at the transition, with one taken beside it: a command's scenario whose
  `given` leaves the unit in the transition's `from`, expecting its event.
  """

  use EhOsContract.DslCase, async: false

  alias EhOsContract.Check.{Completeness, Finding}

  @loans EhOsContract.Fixtures.TransitionLoans

  # The lifecycle's transitions are at lines 15–18 of the file (`contract/2` puts the
  # body at line 4).
  setup_all do
    compile(
      contract("TransitionLoans", """
        aggregate :loan, "Wypożyczenie" do
          identity :loan_id

          invariant :checked_before_return, "Zwrot przyjmuje się po sprawdzeniu sprzętu"

          lifecycle do
            status :open, "Otwarte"
            status :lent, "Wypożyczone"
            status :closed, "Zamknięte", final: true

            initial :open, on: :opened
            transition :open, :lent, :lent
            transition [:open, :lent], :closed, :closed
            transition :lent, :returned, :open
            transition :lent, :noted, :open
          end

          command :open_loan, "Otwórz", by: :reception, emits: :opened
          command :lend, "Wypożycz", by: :reception, emits: :lent
          command :close_loan, "Zamknij", by: :reception, emits: :closed

          command :return_loan, "Zwróć", by: :reception, emits: :returned,
            rejects: :checked_before_return

          event :opened, "Otwarto"
          event :lent, "Wypożyczono"
          event :returned, "Zwrócono"
          event :noted, "Odnotowano", recorded_by: :reception
          event :closed, "Zamknięto", terminal: true
        end

        process :loan, "Wypożyczenie" do
          correlate :loan_id
        end

        scenario "otwarte — wypożyczone" do
          given :opened
          command :lend
          expect :lent
        end

        scenario "wypożyczone — zamknięte" do
          given :opened
          given :lent
          command :close_loan
          expect :closed
        end

        scenario "wypożyczone — zwrot odrzucony" do
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
    assert [{closed, {"transition_loans.ex", 16}}, {returned, {"transition_loans.ex", 17}}] =
             findings()

    # Taken from :lent, not from :open: a transition from two statuses needs both.
    assert closed ==
             "aggregate :loan of #{inspect(@loans)} moves from :open to :closed on :closed, and " <>
               "no scenario of a command starts there and expects it, so nothing shows the " <>
               "implementation takes that transition"

    # A rejected scenario starts in :lent and expects nothing, so it takes nothing.
    assert returned =~ "moves from :lent to :open on :returned"
  end

  test "control: a transition a scenario takes, and one on an event only recorded" do
    messages = Enum.map(findings(), &elem(&1, 0))

    refute Enum.any?(messages, &(&1 =~ "on :lent,"))
    refute Enum.any?(messages, &(&1 =~ "from :lent to :closed"))
    refute Enum.any?(messages, &(&1 =~ ":noted"))
  end
end
