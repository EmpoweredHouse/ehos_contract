defmodule BoundaryRig.SeatingRules do
  @moduledoc """
  **Invented.** The implementation of `BoundaryRig.Enrolment`'s domain service
  `:seating`.

  A test can make the next call return what the declaration does not allow,
  `Process.put(:boundary_rig_seating_misbehaves, true)`, so that the call through the
  contract's module has something to refuse.
  """

  use BoundaryRig.Enrolment, domain_service: :seating

  @impl true
  def free_seats(capacity, taken) do
    if Process.delete(:boundary_rig_seating_misbehaves),
      do: "none",
      else: max(capacity - taken, 0)
  end
end
