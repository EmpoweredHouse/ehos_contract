defmodule EhosContract.Receipt do
  @moduledoc """
  What an accepted command gives back: its id, the events it appended, as the
  contract's structs with `__meta__` set, and their positions. `position` is the
  last of them, what a later query can wait for.

  `duplicate: true` when the same actor's idempotency key had already been accepted:
  the events are that command's, read back, and nothing was appended this time.

  `identity` is the identity of the unit the command went to, `%{booking_id: "0192…"}`:
  for a command that creates an aggregate whose identity is generated, the one the
  library gave it, and for a duplicate, the first command's — or `%{}`
  when that command decided no event, since nothing then says which unit it was.
  """

  # The receipt of v2 §11 and §10.4; a generated identity, plan EM3.

  defstruct [:command_id, :position, identity: %{}, events: [], positions: [], duplicate: false]

  @type t :: %__MODULE__{
          command_id: String.t(),
          identity: %{atom() => String.t()},
          position: pos_integer() | nil,
          events: [struct()],
          positions: [pos_integer()],
          duplicate: boolean()
        }
end
