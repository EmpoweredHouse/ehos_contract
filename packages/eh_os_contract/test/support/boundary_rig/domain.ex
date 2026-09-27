defmodule BoundaryRig.Domain do
  @moduledoc """
  **Invented**, like the rest of `BoundaryRig`. The registrar is a person who
  defines courses and subscribes students; the timetable is the application's own
  code, which releases a seat when a student's schedule no longer fits.
  """

  use EhOsContract.Domain, name: :boundary_rig, language: :en

  context :enrolment, "Enrolment", subdomain: :core

  actor :registrar, :human, "Registrar"
  actor :timetable, :system, "Timetable"

  subdomain :core, "Core", type: :core
end
