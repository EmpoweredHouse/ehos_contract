defmodule EhOsContract.Store do
  @moduledoc """
  Where events are appended and read back.

  It isolates the SQL, not the transaction model. **Every call runs inside the
  caller's Ecto transaction**, so an append commits or rolls back together with
  whatever else the caller wrote.

  ## What an implementation promises

  - **Appends are serialised.** Positions become visible in commit order, with no gap
    a reader has to wait for. A reader that follows `position > checkpoint` therefore
    never skips a row that commits late. Holes left by rolled-back appends are
    permanent and harmless. `EhOsContract.Store.Postgres` gets this from one
    transaction-scoped advisory lock.
  - **A stream's versions have no gaps.** `{:stream, id, expected}` appends only when
    the stream's highest version is `expected` (`0`: the stream must not exist yet).
    The new events get `expected + 1`, `expected + 2`, …. Otherwise the append returns
    `{:error, :wrong_expected_version}` and writes nothing. The entries themselves name
    no stream: the condition does.
  - **`{:dcb, query, after_position}` appends only when nothing matching `query` was
    appended after `after_position`** — the head `c:read_query/2` returned with what it
    read. Otherwise `{:error, :condition_failed}`, and nothing is written.
    Such an append carries no stream: a consistency boundary is a query over the log,
    not a stream of its own.
  - **`:none` appends without a condition**, and then no entry may carry a stream.
    A stream id with no check would be a version nobody verified.
  - **An event's runs are appended with it** (`t:entry/0`), so no event is in the log
    without the runs it belongs to.

  `EhOsContract.Store.Suite` checks all of this. Any implementation can run it.

  ## What it asks of the caller's transaction

  Two things, both from the one global lock, and both new for a host that emitted on
  0.2.1:

  - **READ COMMITTED.** `EhOsContract.Store.Postgres` refuses to append at any other
    isolation level, because under a stricter one the stream check reads a snapshot
    older than the lock. An append inside a REPEATABLE READ or SERIALIZABLE
    transaction now raises.
  - **Take the append lock before any row lock that a reaction in the same
    transaction also takes.** The lock is held from the first append to the end of
    the transaction. Take this order: transaction A locks row R and then appends,
    while transaction B appends and a reaction delivered in its transaction then
    locks R. A waits for the append lock and B waits for R, so Postgres aborts one of
    them as a deadlock. A transaction that locks rows and then appends should call
    `lock/1` first. So should any transaction that appends and then locks rows
    another appender may hold. The lock is re-entrant,
    so taking it early costs nothing.

  ## A query

  `t:query/0` is a list of items, **OR-ed**; an item matches an event of one of its
  `types` carrying **every** one of its `tags`. An item with no tags matches every event
  of its types. `c:read_query/2` returns what matches with the log's head, and the
  head is what the condition checks against: every position up to it is committed,
  since appends commit in position order, so nothing matching up to it means nothing
  matching at all, and the check under the lock reads only what came after it.
  """

  alias EhOsContract.Event

  @typedoc "A place in the global order of appends. The first event is at 1."
  @type position :: pos_integer()

  @typedoc """
  One event to append: the fields of `EhOsContract.Event` except `position` and
  `recorded_at`, which the store assigns. `id` is generated when missing.

  `runs` lists the runs the event belongs to besides its home run, as
  `{process, instance_id}`: the processes of the contracts that `include` it (D7).
  The store writes every run as an `EhOsContract.EventRun` in the same append, the
  home run from the entry's `process` and `instance_id` when it has both.
  """
  @type entry :: map()

  @typedoc "Events of any of `types` carrying all of `tags`; the items of a query are OR-ed."
  @type query_item :: %{types: [String.t(), ...], tags: [String.t()]}

  @typedoc "What a consistency boundary reads: the items are OR-ed (v2 §10.1)."
  @type query :: [query_item()]

  @typedoc "What must hold for an append to happen."
  @type condition ::
          :none
          | {:stream, String.t(), expected_version :: non_neg_integer()}
          | {:dcb, query(), after_position :: non_neg_integer()}

  @typedoc "Why an append was refused."
  @type conflict :: :wrong_expected_version | :condition_failed

  @doc "Takes the append lock for the rest of the caller's transaction."
  @callback lock(repo :: module()) :: :ok

  @doc "Appends `entries`, in order, if `condition` holds."
  @callback append(repo :: module(), [entry()], condition()) ::
              {:ok, [Event.t()]} | {:error, conflict()}

  @doc "One stream's events after `after_version`, in version order."
  @callback read_stream(repo :: module(), String.t(), after_version :: non_neg_integer()) ::
              [Event.t()]

  @doc """
  The events matching `query`, in position order, and the head of the log they were
  read up to: the position to hand to `{:dcb, query, head}`.
  """
  @callback read_query(repo :: module(), query()) :: {[Event.t()], head :: non_neg_integer()}

  @doc "Up to `limit` events after `after_position`, in position order, of the given types or all."
  @callback read_all(
              repo :: module(),
              after_position :: non_neg_integer(),
              limit :: pos_integer(),
              types :: [String.t()] | :all
            ) :: [Event.t()]

  @doc """
  The configured implementation: `config :eh_os_contract, store: MyStore`, and
  `EhOsContract.Store.Postgres` when nothing is configured.
  """
  @spec impl() :: module()
  def impl, do: EhOsContract.Config.get(:store)

  @doc "`c:lock/1` on the configured implementation."
  @spec lock(module()) :: :ok
  def lock(repo), do: impl().lock(repo)

  @doc "`c:append/3` on the configured implementation."
  @spec append(module(), [entry()], condition()) :: {:ok, [Event.t()]} | {:error, conflict()}
  def append(repo, entries, condition), do: impl().append(repo, entries, condition)

  @doc "`c:read_query/2` on the configured implementation."
  @spec read_query(module(), query()) :: {[Event.t()], non_neg_integer()}
  def read_query(repo, query), do: impl().read_query(repo, query)

  @doc "`c:read_stream/3` on the configured implementation."
  @spec read_stream(module(), String.t(), non_neg_integer()) :: [Event.t()]
  def read_stream(repo, stream_id, after_version \\ 0),
    do: impl().read_stream(repo, stream_id, after_version)

  @doc "`c:read_all/4` on the configured implementation."
  @spec read_all(module(), non_neg_integer(), pos_integer(), [String.t()] | :all) :: [Event.t()]
  def read_all(repo, after_position, limit, types \\ :all),
    do: impl().read_all(repo, after_position, limit, types)
end
