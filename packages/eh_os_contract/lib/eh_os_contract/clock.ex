defmodule EhOsContract.Clock do
  @moduledoc """
  The time an event is stamped with, and the one way to choose it (v2 §10.3: "dispatcher
  clock, injectable").

  From v2 plan stage E2 the log is append-only. A test can no longer write an event
  and then move its `occurred_at` with an `UPDATE`. A test that needs a run in the
  past asks for the past up front:

      EhOsContract.Clock.at(~U[2026-07-01 09:00:00Z], fn ->
        EhOsContract.dispatch(Contract, %Receive{request_id: "r-1"}, actor: actor)
      end)

  **Scoped to the calling process, not passed as an option.** An option reaches the
  events the call appends and stops there. Reactions append further events: one
  delivered in the transaction does it in the caller's process, and one delivered
  later does it from a job or a subscription. Carrying the time through a job's
  arguments would be wrong outside tests: a queued reaction runs later, and it must
  stamp the time it actually ran. The process scope reaches every event appended
  while `fun` runs, and no event appended by another process.

  Outside `at/2` this is `DateTime.utc_now/0`, so a host has nothing to configure.
  """

  @key {__MODULE__, :now}

  @doc "The time to stamp an event with: the one set by `at/2`, or now."
  @spec now() :: DateTime.t()
  def now, do: Process.get(@key) || DateTime.utc_now()

  @doc """
  Runs `fun` with every event it appends in this process stamped `at`. Restores
  whatever was set before, so calls nest.

  `at` may be written to any precision. The log stores microseconds, so it is
  widened to six digits here rather than refused at the append. It must be in UTC,
  which is what the log stores: converting needs a time zone database, and that is
  the caller's to choose, so a time in another zone is refused here, at the call.
  """
  @spec at(DateTime.t(), (-> result)) :: result when result: term()
  def at(%DateTime{time_zone: "Etc/UTC", microsecond: {value, _precision}} = at, fun)
      when is_function(fun, 0) do
    previous = Process.put(@key, %{at | microsecond: {value, 6}})

    try do
      fun.()
    after
      if previous, do: Process.put(@key, previous), else: Process.delete(@key)
    end
  end

  def at(%DateTime{time_zone: zone}, _fun) do
    raise ArgumentError,
          "EhOsContract.Clock.at/2 got a time in #{zone}. The log stores UTC: convert it " <>
            "first, e.g. with DateTime.shift_zone!(at, \"Etc/UTC\")"
  end
end
