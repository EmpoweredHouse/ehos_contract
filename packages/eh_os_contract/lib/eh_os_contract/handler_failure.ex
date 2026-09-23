defmodule EhOsContract.HandlerFailure do
  @moduledoc """
  The trace a synchronous handler leaves when it dies (ADR §13).

  A synchronous handler runs inside the emitting transaction, so its exception rolls
  back the handling row **and the event**. That is the right semantics — nothing
  happened, so the log must not claim it did — and it produces the one gap the ADR
  found by building the third verification layer: the most interesting failure
  leaves no trace in the artifact that exists to make failures visible.

  ## Why this is a separate table and not a status

  Every other row in the log is a statement about something that happened. This one
  is a statement about something that was **attempted and did not happen**, so it
  cannot reference an event: the event was rolled back and never existed. What
  survives is the `correlation_id`, generated before the transaction opened.

  ## Why it is not only telemetry

  Telemetry is emitted as well, and error collection belongs to the client's error
  tooling rather than here. But telemetry only exists where somebody configured a
  collector, and the gap is about the **artifact**, not about observability — a
  report that cannot say whether a path was ever attempted is wrong on its own
  terms, no matter what Datadog holds.

  Which is also why this table has a reader from the first commit: without one it
  would be another declaration nobody consults, and stage 2 exists to remove those.
  `EhOsContract.Conformance` uses it to tell *never attempted* from *attempted and failing*,
  two things a path report otherwise reports identically as a dead path.

  ## Where the write happens, and the limit that follows

  It cannot happen where the failure is noticed: that code is inside the doomed
  transaction, so its insert would roll back too. It happens in the emitter's
  outermost frame — the one that opened the transaction — **after** the rollback,
  when the connection is free again. No second connection, no task, no writing
  around the sandbox in tests.

  The limit that follows is real and stated rather than hidden: when the caller
  opened the transaction themselves, this module never gets its turn. The exception
  propagates into their transaction and the failure is theirs to record. For a
  handler emitting into an already-open transaction that is the correct division —
  they own the rollback, so they own the trace.
  """

  use Ecto.Schema

  import Ecto.Query

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "pns_handler_failures" do
    field(:contract, :string)
    field(:event_type, :string)
    field(:handler, :string)
    field(:correlation_id, :binary_id)
    field(:instance_id, :string)
    field(:error, :string)
    field(:occurred_at, :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  @doc """
  Records one synchronous handler failure, outside the transaction that rolled back.

  Takes the context off `EhOsContract.SyncHandlerError`, which is what carries it out of
  dispatch — the frame that notices the failure and the frame that can durably write
  it are not the same one, so the context has to travel.
  """
  @spec record!(EhOsContract.SyncHandlerError.t(), DateTime.t()) :: t()
  def record!(%EhOsContract.SyncHandlerError{} = failure, now \\ DateTime.utc_now()) do
    repo().insert!(%__MODULE__{
      contract: inspect(failure.contract),
      event_type: to_string(failure.event_type),
      handler: inspect(failure.handler),
      correlation_id: failure.correlation_id,
      instance_id: failure.instance_id,
      error: Exception.message(failure.original),
      occurred_at: now
    })
  end

  @doc """
  How many runs each handler failed on, over a period.

  Counts **distinct runs**, not failures: a handler retried forty times for one
  client is one failing run, and the number that matters when a path is not being
  taken is how many runs are affected. Handlers whose failures carry no run identity
  are counted once each, since the alternative is dropping them from a report about
  why nothing is happening.
  """
  @spec runs_by_handler(keyword()) :: %{String.t() => non_neg_integer()}
  def runs_by_handler(opts \\ []) do
    from(f in __MODULE__)
    |> bound(:>=, Keyword.get(opts, :since))
    |> bound(:<=, Keyword.get(opts, :until))
    |> group_by([f], f.handler)
    # The fallback needs an explicit cast: `instance_id` is text and `id` a uuid, and
    # Postgres refuses to coalesce the two rather than picking one silently.
    |> select(
      [f],
      {f.handler, count(fragment("distinct coalesce(?, cast(? as text))", f.instance_id, f.id))}
    )
    |> repo().all()
    |> Map.new()
  end

  @spec bound(Ecto.Query.t(), :>= | :<=, DateTime.t() | nil) :: Ecto.Query.t()
  defp bound(query, _direction, nil), do: query
  defp bound(query, :>=, at), do: where(query, [f], f.occurred_at >= ^at)
  defp bound(query, :<=, at), do: where(query, [f], f.occurred_at <= ^at)

  # **Read at run time, not at compile time — and that changed when the engine
  # became its own application (2026-08-20).** `Application.compile_env!/2`
  # resolved to the host's repo module while compiling this package, and a package
  # compiles before the application that configures it: every call site warned that
  # the host's repo module was undefined, and in a real consumer it would warn about
  # theirs. A library cannot hold a compile-time reference to a module its user
  # has not written yet.
  #
  # What is lost is `compile_env!`'s check that configuration has not changed since
  # the build. What is gained is that this compiles standing alone, which is the
  # whole point of a package.
  defp repo, do: Application.fetch_env!(:eh_os_contract, :repo)
end
