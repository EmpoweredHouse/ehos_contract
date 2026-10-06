defmodule PhaseRig do
  @moduledoc """
  **An engine fixture, and invented.** A visit booked and moved, written for the two
  step shapes that do not map one step to one relation of the graph (plan E13a, the
  user's decisions of 6 October): a policy handling two events with one command, and
  a process manager issuing one command on one event both as the event starts a run
  and during it. No workshop stands behind it, and no name in it comes from one.
  """

  use Boundary, deps: [EhOsContract], exports: [Domain, Visits]
end
