defmodule ProcessShapes.Batching do
  @moduledoc """
  # THIS IS NOT A DOMAIN EITHER. See `ProcessShapes`.

  A process that promises nothing and a run keyed by two fields (v2 plan, E7c), over
  `ProcessShapes.Bare`'s batches. Until plan DD, P2g (#228) it was `:batching` inside
  the contract.
  """

  use EhosContract.Process,
    id: "process_shapes.batching",
    domain: ProcessShapes.Domain,
    label: "Batch run"

  correlate [:tenant_id, :batch_id]

  stage :running, include: [{ProcessShapes.Bare, [:batch_opened, :batch_closed]}]

  ends_on :batch_closed
end
