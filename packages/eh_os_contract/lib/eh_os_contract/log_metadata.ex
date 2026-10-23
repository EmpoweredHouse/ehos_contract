defmodule EhOsContract.LogMetadata do
  # The correlation identifier, one across every application it passes through, of the work the
  # engine is doing, as the Logger's process metadata `correlation_id`, so every line an
  # application logs while the engine runs a command, records an event or reacts to one carries it
  # (#298); `docs/` tells a host the key. It is set for as long as the work runs and what was
  # there before is put back: a process that handles one event after another never writes one's
  # identifier on the next one's lines.
  @moduledoc false

  @doc """
  Runs `fun` with the Logger's `correlation_id` set to `correlation_id`, and puts back the value
  before it, or none, however `fun` ends. The identifier is written as the log keeps it, in lower
  case, so a work's lines carry one spelling whether they come from its command or from its events
  read back. With anything but a UUID's text, as a host's own option or another application's
  message may hold, runs `fun` as it is, leaving the metadata as it was.
  """
  @spec correlated(term(), (-> result)) :: result when result: term()
  def correlated(correlation_id, fun) do
    case uuid(correlation_id) do
      {:ok, uuid} -> set(uuid, fun)
      :error -> fun.()
    end
  end

  # The 36-byte check leaves out the 16 raw bytes `Ecto.UUID.cast/1` also takes.
  defp uuid(id) when is_binary(id) and byte_size(id) == 36, do: Ecto.UUID.cast(id)
  defp uuid(_id), do: :error

  defp set(correlation_id, fun) do
    before = Logger.metadata()[:correlation_id]
    Logger.metadata(correlation_id: correlation_id)

    try do
      fun.()
    after
      # `nil` removes the key, as it was before when there was none.
      Logger.metadata(correlation_id: before)
    end
  end
end
