defmodule AppuniteEquipment.Contracts.Assignments do
  @moduledoc """
  One assignment of a computer to an employee, from the issue to the computer
  arriving back in the office: the run the process owner chose to verify
  (distillation, shape B).

  It decides nothing. Every decision about a computer is
  `AppuniteEquipment.Contracts.Computers`'s, because every rule is about one
  computer; this contract takes the three events of an assignment from it and
  declares their order, which the computer's own run cannot, since a computer goes
  round the loop many times. So the report can say, per assignment, which ones were
  issued and never came back, and which came back without a return being started.

  An assignment that is never returned is not a defect: an employee may keep a
  replacement (E), and an employee who stays keeps the computer for years.
  """

  use EhOsContract.Contract, domain: AppuniteEquipment.Domain, context: :equipment

  consumes AppuniteEquipment.Contracts.Computers, [
    :issued,
    :return_started,
    :returned
  ]

  process :assignment, "Przydział: od wydania komputera do jego powrotu do biura",
    accountable: :equipment_manager do
    correlate :assignment_id

    stage :issue do
      include :issued
    end

    # Two stages, not one: a parcel that arrives with no return started is a path the
    # report should show, and inside one stage no order is claimed.
    stage :return do
      include :return_started
    end

    stage :arrival do
      include :returned, terminal: true
    end
  end
end
