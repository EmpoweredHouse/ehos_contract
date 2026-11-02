defmodule EhOsContract.Store do
  @moduledoc """
  Appends events to the log, and reads them back. The default is
  `EhOsContract.Store.Postgres`.

  The Store hides the SQL. It does not have a transaction of its own:
  `c:append/3` and `c:lock/1` run inside the Ecto transaction of the caller, and raise
  outside one. So an append commits or rolls back together with each other write of
  the caller.

  An append of no entries is the exception. `EhOsContract.Store.Postgres` returns
  `{:ok, []}` for it. It checks no condition, and it does not raise outside a
  transaction.

  ## What an implementation promises

  `EhOsContract.Store.Suite` checks each of these promises. Any implementation can
  run it.

  - **Appends happen one at a time.** Positions become visible in the order of the
    commits, with no gap that a reader must wait for. So a reader that follows
    `position > checkpoint` never skips a row that commits late. An append that rolls
    back leaves a hole. The hole stays, and does no harm.
    `EhOsContract.Store.Postgres` gets this order from one advisory lock for each
    transaction.
  - **The versions of a stream have no gaps.** `{:stream, id, expected}` appends
    only if the highest version of the stream is `expected`. With `0`, the stream
    must not exist yet. The new events get `expected + 1`, `expected + 2`, and so on.
    Otherwise the append returns `{:error, :wrong_expected_version}`, and writes
    nothing. The condition names the stream; the entries do not.
  - **`{:dcb, query, after_position}` appends only if no event that matches `query`
    came after `after_position`.** That position is the head that
    `c:read_query/2` returned. Otherwise the append returns
    `{:error, :condition_failed}`, and writes nothing. Such an append has no stream:
    a consistency boundary is a query over the log, not a stream of its own.
  - **`:none` appends with no condition.** Then no entry can name a stream, because
    nothing checks the version of that stream.
  - **An event and its runs go in one append** (`t:entry/0`). So the log holds no
    event without the runs that it belongs to.

  ## What it asks of the transaction of the caller

  Both rules come from the one global lock.

  - **Use READ COMMITTED.** `EhOsContract.Store.Postgres` raises on an append at any
    other isolation level. At a stricter level, the check of the stream reads a
    snapshot older than the lock.
  - **Take the append lock before a row lock that a reaction can take.** The
    reaction runs in the same transaction. The lock stays from the first append to the end of the
    transaction.

  Example of a deadlock: transaction A locks row R, and then appends. Transaction B
  appends, and then a reaction in its transaction locks R. A waits for the append
  lock, and B waits for R. Postgres stops one of them as a deadlock.

  - If a transaction locks rows and then appends, call `c:lock/1` first.
  - If a transaction appends and then locks rows that another appender can hold, call
    `c:lock/1` first too.

  The lock is re-entrant, so an early `c:lock/1` costs nothing.

  ## A query

  `t:query/0` is a list of items. An event matches the query if it matches one item.
  An event matches an item if it is of one of its `types`, and carries each of its
  `tags`. An item with no tags matches each event of its types.

  `c:read_query/2` returns the events that match, and the head of the log. The
  condition `{:dcb, query, head}` checks against that head:

  - appends commit in the order of their positions, so each position up to the head
    is committed;
  - so if nothing matched up to the head, nothing matches there at all;
  - so the check under the lock reads only what came after the head.
  """

  alias EhOsContract.Event

  @typedoc "A place in the global order of appends. The first event is at 1."
  @type position :: pos_integer()

  @typedoc """
  One event to append: the fields of `EhOsContract.Event` except `position` and
  `recorded_at`, which the store assigns. `id` is generated when missing.

  `runs` lists the runs the event belongs to, as `{process, instance_id}`: the
  process modules that `include` it, each with the key of the run. The store writes
  every run as an `EhOsContract.EventRun` in the same append, a run named twice once.
  """
  @type entry :: map()

  @typedoc "Events of any of `types` carrying all of `tags`; the items of a query are OR-ed."
  @type query_item :: %{types: [String.t(), ...], tags: [String.t()]}

  # A consistency boundary's query, v2 §10.1.
  @typedoc "What a consistency boundary reads: the items are OR-ed."
  @type query :: [query_item()]

  @typedoc "What must hold for an append to happen."
  @type condition ::
          :none
          | {:stream, String.t(), expected_version :: non_neg_integer()}
          | {:dcb, query(), after_position :: non_neg_integer()}

  @typedoc "Why an append was refused."
  @type conflict :: :wrong_expected_version | :condition_failed

  @doc "Takes the append lock until the end of the transaction of the caller."
  @callback lock(repo :: module()) :: :ok

  @doc """
  Appends `entries` in their order, if `condition` holds. Returns the appended events,
  or the conflict.
  """
  @callback append(repo :: module(), [entry()], condition()) ::
              {:ok, [Event.t()]} | {:error, conflict()}

  @doc "Returns the events of one stream after `after_version`, in the order of their versions."
  @callback read_stream(repo :: module(), String.t(), after_version :: non_neg_integer()) ::
              [Event.t()]

  @doc """
  Returns the events that match `query`, in the order of their positions, and the
  head of the log that the read reached. Give that head to `{:dcb, query, head}`.
  """
  @callback read_query(repo :: module(), query()) :: {[Event.t()], head :: non_neg_integer()}

  @doc """
  Returns up to `limit` events after `after_position`, in the order of their
  positions. `types` limits the events to those types; `:all` takes each type.
  """
  @callback read_all(
              repo :: module(),
              after_position :: non_neg_integer(),
              limit :: pos_integer(),
              types :: [String.t()] | :all
            ) :: [Event.t()]

  # The configured implementation: `config :eh_os_contract, store: MyStore`, and
  # `EhOsContract.Store.Postgres` when nothing is configured.
  @doc false
  @spec impl() :: module()
  def impl, do: EhOsContract.Config.get(:store)

  @doc "`c:lock/1` on the configured implementation."
  @spec lock(module()) :: :ok
  def lock(repo), do: impl().lock(repo)

  # `c:append/3` on the configured implementation.
  # Called by dispatcher.ex, personal.ex, timer_job.ex.
  @doc false
  @spec append(module(), [entry()], condition()) :: {:ok, [Event.t()]} | {:error, conflict()}
  def append(repo, entries, condition), do: impl().append(repo, entries, condition)

  # `c:read_query/2` on the configured implementation.
  # Called by dispatcher.ex.
  @doc false
  @spec read_query(module(), query()) :: {[Event.t()], non_neg_integer()}
  def read_query(repo, query), do: impl().read_query(repo, query)

  # `c:read_stream/3` on the configured implementation.
  # Called by dispatcher.ex, timer_job.ex.
  @doc false
  @spec read_stream(module(), String.t(), non_neg_integer()) :: [Event.t()]
  def read_stream(repo, stream_id, after_version \\ 0),
    do: impl().read_stream(repo, stream_id, after_version)

  # `c:read_all/4` on the configured implementation.
  # Called by subscription.ex.
  @doc false
  @spec read_all(module(), non_neg_integer(), pos_integer(), [String.t()] | :all) :: [Event.t()]
  def read_all(repo, after_position, limit, types \\ :all),
    do: impl().read_all(repo, after_position, limit, types)
end
