defmodule ProcessShapes.Bare do
  @moduledoc """
  # THIS IS NOT A DOMAIN EITHER. See `ProcessShapes`.

  The batch whose run promises nothing and is keyed by two fields (v2 plan, E7c),
  `ProcessShapes.Batching`'s since plan DD, P2g (#228). Its two events come from two
  commands, since an event in v2 is decided or recorded, never written around
  dispatch.
  """

  use EhOsContract.Contract,
    domain: ProcessShapes.Domain,
    context: :batching,
    id: "process_shapes.bare"

  aggregate :batch, "Batch" do
    identity [:tenant_id, :batch_id]

    command :open_batch, "Open a batch", by: :batch_operator, emits: :batch_opened
    command :close_batch, "Close a batch", by: :batch_operator, emits: :batch_closed

    event :batch_opened, "Batch opened"
    event :batch_closed, "Batch closed"
  end
end

defmodule ProcessShapes.Batch do
  @moduledoc "The decider of `ProcessShapes.Bare`'s batch."

  use ProcessShapes.Bare, aggregate: :batch

  @impl true
  def open_batch(%OpenBatch{tenant_id: tenant, batch_id: batch}, _state),
    do: emit(%BatchOpened{tenant_id: tenant, batch_id: batch})

  @impl true
  def close_batch(%CloseBatch{tenant_id: tenant, batch_id: batch}, _state),
    do: emit(%BatchClosed{tenant_id: tenant, batch_id: batch})
end
