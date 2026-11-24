defmodule EhosContract.Meta do
  @moduledoc """
  What a command or an event carries besides its fields: who acted, when,
  and which run and which cause it belongs to. Every struct a contract generates has
  it as `__meta__`, a name no declared field may take (F1).

  A decision reads it and never writes it: dispatch sets it on a command, and the
  store on an event it appends. `evolve/2` may take a business date from
  `occurred_at` this way. An event read back from the log also carries its `id`
  and its `position`; a command has neither.
  """

  # The meta of v2 §5; the business date read from it, v2 §4.5.

  defstruct [:actor, :occurred_at, :correlation_id, :causation_id, :id, :position]

  @typedoc "Set by dispatch and by the store, not by a decision."
  @type t :: %__MODULE__{
          actor: term(),
          occurred_at: DateTime.t() | nil,
          correlation_id: String.t() | nil,
          causation_id: String.t() | nil,
          id: String.t() | nil,
          position: pos_integer() | nil
        }
end
