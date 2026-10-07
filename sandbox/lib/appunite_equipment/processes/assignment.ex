defmodule AppuniteEquipment.Processes.Assignment do
  @moduledoc """
  One assignment of a computer to an employee, from the issue to the computer
  arriving back in the office: the run the process owner chose to verify
  (distillation, shape B). Until plan DD, P2f (#222) it was the whole of a contract,
  `AppuniteEquipment.Contracts.Assignments`, which decided nothing and only declared
  this run over `AppuniteEquipment.Contracts.Computers`'s events.

  Every decision about a computer is the computer's, because every rule is about one
  computer; this module declares the order of one issue and its return, which the
  computer's lifecycle cannot: a computer goes round the loop many times, and its
  lifecycle says where it is, not which issue a return answers. So the report can
  say, per assignment, which ones were issued and never came back, and which came
  back without a return being started.

  A computer stolen from the employee ends the assignment too: `lost` names it. An
  assignment that is never returned is not a defect: an employee may keep a
  replacement (E), and an employee who stays keeps the computer for years.
  """

  use EhOsContract.Process,
    id: "appunite_equipment.assignment",
    domain: AppuniteEquipment.Domain,
    label: "Przydział: od wydania komputera do jego powrotu do biura",
    accountable: :equipment_manager

  correlate :assignment_id

  stage :issue, include: [{AppuniteEquipment.Contracts.Computers, :issued}]

  # Two stages, not one: a parcel that arrives with no return started is a path the
  # report should show, and inside one stage no order is claimed. A theft ends an
  # assignment as a return does: the computer will not come back.
  stage :return, include: [{AppuniteEquipment.Contracts.Computers, [:return_started, :lost]}]

  stage :arrival, include: [{AppuniteEquipment.Contracts.Computers, :returned}]

  ends_on [:lost, :returned]
end
