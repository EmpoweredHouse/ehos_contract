defmodule EhosContract.NewerSchemaError do
  @moduledoc """
  A row of the log written with a newer version of its event's fields than the
  running code declares: code older than the code that wrote it, as on a
  node not yet upgraded during a rolling deploy, or after a rollback.

  It is not a defect of the event, and nothing is decoded with fields that may mean
  something else. A command whose stream holds such a row is refused, recorded
  `failed` with this module as its error. A subscription, a process manager and a
  relay wait at the row: nothing moves, no attempt is counted, and they go on by
  themselves once the node runs code that declares the version. An effect's job is
  snoozed the same way. The message names the row, never a value.
  """

  # Waiting at a row written by newer code: plan W1.

  defexception [:contract, :type, :position, :written, :declared]

  @type t :: %__MODULE__{
          contract: String.t(),
          type: String.t(),
          position: pos_integer() | nil,
          written: pos_integer(),
          declared: pos_integer()
        }

  @impl true
  def message(error) do
    "#{error.contract} holds #{inspect(error.type)} at position #{error.position} written " <>
      "with schema version #{error.written}, newer than the #{error.declared} this code " <>
      "declares: the code reading it is older than the code that wrote it"
  end
end
