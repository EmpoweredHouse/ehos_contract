defmodule BoundaryRig.SeatingRules do
  @moduledoc """
  **Invented.** The implementation of `BoundaryRig.Enrolment`'s domain service
  `:seating`.

  A test can make the next call return what the declaration does not allow,
  `Process.put(:boundary_rig_seating_misbehaves, true)`, or nil, which it does not
  declare optional, `Process.put(:boundary_rig_seating_misbehaves_with_nil, true)`, so
  that the call through the contract's module has something to refuse.
  """

  use BoundaryRig.Enrolment, domain_service: :seating

  @impl true
  def free_seats(capacity, taken) do
    cond do
      Process.delete(:boundary_rig_seating_misbehaves) -> "none"
      Process.delete(:boundary_rig_seating_misbehaves_with_nil) -> nil
      true -> max(capacity - taken, 0)
    end
  end

  @impl true
  def next_seat(capacity, taken) when taken < capacity, do: taken + 1
  def next_seat(_capacity, _taken), do: nil
end
