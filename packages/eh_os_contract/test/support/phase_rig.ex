defmodule PhaseRig do
  @moduledoc """
  **An engine fixture, and invented.** A visit booked, moved and closed, written for
  the step shapes that do not map one step to one relation of the graph (plan E13a,
  the user's decisions of 6 and 7 October): a policy handling two events with one
  command, whose relation carries each step's numbers by trigger, and a process
  manager issuing one command on one event both as the event starts a run and during
  it, whose two relations get no numbers. Its manager also starts and ends a run on
  one event, for the runtime's test of that shape. No workshop stands behind it, and
  no name in it comes from one.
  """

  use Boundary, deps: [EhOsContract], exports: [Domain, Visits]
end
