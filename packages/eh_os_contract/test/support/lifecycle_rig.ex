defmodule LifecycleRig do
  @moduledoc """
  **An engine fixture, and invented.** A visit to a clinic, written to exercise an
  aggregate's lifecycle at run time (plan LC2, #99), and nothing more: no workshop
  stands behind it, and no name in it comes from one. A visit is booked, the patient
  arrives, the visit closes; a booked visit can be cancelled; notes are taken at any
  point of an open visit.
  """

  use Boundary, deps: [EhOsContract], exports: [Domain, Visits]
end
