defmodule ProcessShapes.Timing do
  @moduledoc """
  # THIS IS NOT A DOMAIN EITHER. See `ProcessShapes`.

  A timed run (v2 plan, E7c) over `ProcessShapes.Timed`'s events: it starts, is
  acknowledged, and ends on `run_finished`, and is promised to take an hour, a
  confirmed `deadline`. Until plan DD, P2g (#228) it was `:timed_run` inside the
  contract.
  """

  use EhOsContract.Process,
    id: "process_shapes.timing",
    domain: ProcessShapes.Domain,
    label: "Timed run",
    accountable: :run_owner

  correlate :run_id

  stage :opening, "Opening", include: [{ProcessShapes.Timed, [:run_started, :run_acknowledged]}]
  stage :closing, "Closing", include: [{ProcessShapes.Timed, :run_finished}]

  ends_on :run_finished

  deadline {1, :hour}
end
