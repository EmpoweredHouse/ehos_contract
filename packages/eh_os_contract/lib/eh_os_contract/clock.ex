defmodule EhOsContract.Clock do
  @moduledoc """
  The time an event is stamped with, and the one way to choose it (v2 §10.3: "dispatcher
  clock, injectable").

  From v2 plan stage E2 the log is append-only. A test can no longer write an event
  and then move its `occurred_at` with an `UPDATE`. A test that needs a run in the
  past asks for the past up front:

      EhOsContract.Clock.at(~U[2026-07-01 09:00:00Z], fn ->
        EhOsContract.emit!(Contract, :request_received, %{request_id: "r-1"})
      end)

  **Scoped to the calling process, not passed in `ctx`.** A `ctx` key reaches the
  events the caller emits and stops there. Handlers emit further events: a
  synchronous handler does it in the caller's process, and an asynchronous one does
  it from a job. `Oban.drain_queue/2` in a test also runs the job in the caller's
  process, but the job builds its `ctx` from its arguments. Carrying the time
  through job arguments would be wrong outside tests: a queued handler runs later,
  and it must stamp the time it actually ran. The process scope reaches every event
  emitted while `fun` runs, and no event emitted by another process.

  Outside `at/2` this is `DateTime.utc_now/0`, so a host has nothing to configure.
  """

  @key {__MODULE__, :now}

  @doc "The time to stamp an event with: the one set by `at/2`, or now."
  @spec now() :: DateTime.t()
  def now, do: Process.get(@key) || DateTime.utc_now()

  @doc """
  Runs `fun` with every event it emits in this process stamped `at`. Restores
  whatever was set before, so calls nest.

  `at` may be written to any precision. The log stores microseconds, so it is
  widened to six digits here rather than refused at the append.
  """
  @spec at(DateTime.t(), (-> result)) :: result when result: term()
  def at(%DateTime{microsecond: {value, _precision}} = at, fun) when is_function(fun, 0) do
    previous = Process.put(@key, %{at | microsecond: {value, 6}})

    try do
      fun.()
    after
      if previous, do: Process.put(@key, previous), else: Process.delete(@key)
    end
  end
end
