defmodule ProcessShapes.Bare do
  @moduledoc """
  # THIS IS NOT A DOMAIN EITHER. See `ProcessShapes.Rig`.

  **The shape of a periodic process that promises nothing.** No `trace`, no
  `external`, no handler — a run somebody wants watched for order and coverage,
  due on a cadence, with nobody having put a number on how fast any of it has to
  happen.

  It also carries the two shapes the other invented fixtures do not have: a run
  keyed by **two** fields, and a `cadence`. Both were reachable only through the
  TaxVision contract until 2026-08-21, so every test contrasting "one field" with
  "two" or "has a cadence" with "has none" had a client contract on one side of
  the comparison.

  It exists because two of the engine's outputs have a branch that only this shape
  reaches: the brief says "this process has no deadline and does not need one"
  instead of leaving a hole where the promises were, and it omits the outside
  dependencies section entirely rather than printing an empty one. Both branches
  were reachable only through a client contract until 2026-08-21, so the engine's
  own suite could not see them.

  Separate from `ProcessShapes.Rig` rather than a second process inside it: the rig
  is what a dozen tests count events and edges against, and adding two events to it
  to reach a rendering branch would make those counts depend on a fixture change
  they have nothing to do with.
  """

  use PNS.Contract

  event :batch_opened,
    label: "Batch opened",
    owner: ProcessShapes.Bare,
    payload: %{tenant_id: :id, batch_id: :id},
    process: :batching,
    stage: :running

  event :batch_closed,
    label: "Batch closed",
    owner: ProcessShapes.Bare,
    payload: %{tenant_id: :id, batch_id: :id},
    process: :batching,
    stage: :running,
    terminal: true

  process :batching,
    label: "Batch run",
    stages: [:running],
    # Two fields, like an accounting month and unlike a treatment episode. A run
    # is one tenant's one batch.
    instance: [:tenant_id, :batch_id],
    # Due once a week. Nothing here promises how quickly anything inside a run
    # finishes — that is `trace`, and this process deliberately has none.
    cadence: {1, :week}
end
