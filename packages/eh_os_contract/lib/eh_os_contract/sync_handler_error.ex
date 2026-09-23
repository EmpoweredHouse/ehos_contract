defmodule EhOsContract.SyncHandlerError do
  @moduledoc """
  Carries a synchronous handler's failure out of dispatch, so it can be recorded
  where a write survives.

  It exists because the frame that knows *which handler failed on which run* is deep
  inside a transaction that is about to disappear, and the frame that can write
  durably knows none of that. Wrapping is the only way for the context to make the
  trip.

  **It is transport and never reaches a caller.** The emitter unwraps it and reraises
  the handler's own exception with the handler's own stacktrace, so client code that
  rescues a specific error still rescues it. Letting the wrapper out would turn a
  diagnostic mechanism into a breaking change in every caller's error handling —
  which is a steep price for a better message, and the message is available on the
  telemetry event and the recorded row anyway.

  Carrying the stacktrace is what makes that unwrapping honest: reraising the original
  with the *current* stacktrace would point at the emitter rather than at the handler,
  and a trace that points at the library is worse than no wrapper at all.
  """

  defexception [
    :handler,
    :contract,
    :event_type,
    :correlation_id,
    :instance_id,
    :original,
    :stacktrace
  ]

  @type t :: %__MODULE__{}

  @impl Exception
  def message(%__MODULE__{} = error) do
    run = error.instance_id || "unknown run"

    "#{inspect(error.handler)} failed while handling #{inspect(error.event_type)} " <>
      "(#{run}): #{Exception.message(error.original)}"
  end
end
