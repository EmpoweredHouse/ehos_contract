defmodule EhOsContract.Store do
  @moduledoc """
  Where events are appended and read back (v2 §10.1).

  It isolates the SQL, not the transaction model. **Every call runs inside the
  caller's Ecto transaction**, so an append commits or rolls back together with
  whatever else the caller wrote, as a v1 emission always has.

  ## What an implementation promises

  - **Appends are serialised.** Positions become visible in commit order, with no gap
    a reader has to wait for. A reader that follows `position > checkpoint` therefore
    never skips a row that commits late. Holes left by rolled-back appends are
    permanent and harmless. `EhOsContract.Store.Postgres` gets this from one
    transaction-scoped advisory lock (v2 §10.2).
  - **A stream's versions have no gaps.** `{:stream, id, expected}` appends only when
    the stream's highest version is `expected` (`0`: the stream must not exist yet).
    The new events get `expected + 1`, `expected + 2`, …. Otherwise the append returns
    `{:error, :wrong_expected_version}` and writes nothing.
  - **`:none` appends without a condition**, and then no entry may carry a stream.
    A stream id with no check would be a version nobody verified.

  `EhOsContract.Store.Suite` checks all of this. Any implementation can run it.

  ## Not yet

  v2 §10.1 also has a `{:dcb, query, after}` condition and `read_query/2`. They arrive
  with the first contract that needs a consistency boundary wider than one stream
  (v2 plan, E9), so that the kind of condition comes with its first reader.
  """

  alias EhOsContract.Event

  @typedoc "A place in the global order of appends. The first event is at 1."
  @type position :: pos_integer()

  @typedoc """
  One event to append: the fields of `EhOsContract.Event` except `position` and
  `recorded_at`, which the store assigns. `id` is generated when missing.
  """
  @type entry :: map()

  @typedoc "What must hold for an append to happen."
  @type condition :: :none | {:stream, String.t(), expected_version :: non_neg_integer()}

  @doc "Takes the append lock for the rest of the caller's transaction."
  @callback lock(repo :: module()) :: :ok

  @doc "Appends `entries`, in order, if `condition` holds."
  @callback append(repo :: module(), [entry()], condition()) ::
              {:ok, [Event.t()]} | {:error, :wrong_expected_version}

  @doc "One stream's events after `after_version`, in version order."
  @callback read_stream(repo :: module(), String.t(), after_version :: non_neg_integer()) ::
              [Event.t()]

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
  def impl, do: Application.get_env(:eh_os_contract, :store, EhOsContract.Store.Postgres)

  @doc "`c:append/3` on the configured implementation."
  @spec append(module(), [entry()], condition()) ::
          {:ok, [Event.t()]} | {:error, :wrong_expected_version}
  def append(repo, entries, condition), do: impl().append(repo, entries, condition)

  @doc "`c:read_stream/3` on the configured implementation."
  @spec read_stream(module(), String.t(), non_neg_integer()) :: [Event.t()]
  def read_stream(repo, stream_id, after_version \\ 0),
    do: impl().read_stream(repo, stream_id, after_version)

  @doc "`c:read_all/4` on the configured implementation."
  @spec read_all(module(), non_neg_integer(), pos_integer(), [String.t()] | :all) :: [Event.t()]
  def read_all(repo, after_position, limit, types \\ :all),
    do: impl().read_all(repo, after_position, limit, types)
end
