defmodule EhOsContract.Store.Postgres do
  @moduledoc """
  `EhOsContract.Store` on the table migration V03 builds (v2 §10.2–10.4).

  Every append takes `eh_os_contract_append_lock()`, a transaction-scoped advisory
  lock with one fixed key. The table's own trigger takes the same lock for inserts
  that go around this module, and the lock is re-entrant, so the second acquisition
  costs nothing. While one transaction holds it, every other append waits. Positions
  therefore commit in the order they were handed out, and a stream's highest version
  cannot move between being read and being written.

  The isolation level must be READ COMMITTED. Each statement after the lock then sees
  whatever the previous lock holder committed. Under REPEATABLE READ the snapshot is
  older than the lock, and the version check would read a stale stream. This module
  refuses to append at any other level instead of trusting the configuration.
  """

  @behaviour EhOsContract.Store

  import Ecto.Query

  alias EhOsContract.Event

  @writable ~w(id type schema_version contract contract_version stream_id stream_version tags
               process instance_id command_id correlation_id causation_id actor occurred_at
               payload metadata)a

  @impl true
  @spec lock(module()) :: :ok
  def lock(repo) do
    in_transaction!(repo)

    case repo.query!(
           "SELECT eh_os_contract_append_lock(), current_setting('transaction_isolation')",
           [],
           log: false
         ).rows do
      [[_, "read committed"]] ->
        :ok

      [[_, level]] ->
        raise ArgumentError,
              "EhOsContract.Store.Postgres appends only under READ COMMITTED, and this " <>
                "transaction runs at #{level}. Under a stricter level the check of a " <>
                "stream's version reads a snapshot older than the append lock."
    end
  end

  @impl true
  @spec append(module(), [EhOsContract.Store.entry()], EhOsContract.Store.condition()) ::
          {:ok, [Event.t()]} | {:error, :wrong_expected_version}
  def append(_repo, [], _condition), do: {:ok, []}

  def append(repo, entries, condition) when is_list(entries) do
    rows = Enum.map(entries, &row!/1)
    lock(repo)

    with {:ok, rows} <- apply_condition(repo, rows, condition) do
      {_count, events} = repo.insert_all(Event, rows, returning: true)
      {:ok, Enum.sort_by(events, & &1.position)}
    end
  end

  @impl true
  @spec read_stream(module(), String.t(), non_neg_integer()) :: [Event.t()]
  def read_stream(repo, stream_id, after_version) do
    repo.all(
      from(e in Event,
        where: e.stream_id == ^stream_id and e.stream_version > ^after_version,
        order_by: e.stream_version
      )
    )
  end

  @impl true
  @spec read_all(module(), non_neg_integer(), pos_integer(), [String.t()] | :all) :: [Event.t()]
  def read_all(repo, after_position, limit, types) do
    query =
      from(e in Event, where: e.position > ^after_position, order_by: e.position, limit: ^limit)

    query = if types == :all, do: query, else: where(query, [e], e.type in ^types)
    repo.all(query)
  end

  @spec apply_condition(module(), [map()], EhOsContract.Store.condition()) ::
          {:ok, [map()]} | {:error, :wrong_expected_version}
  defp apply_condition(_repo, rows, :none) do
    if Enum.any?(rows, &Map.get(&1, :stream_id)) do
      raise ArgumentError,
            "an append with condition :none carries a stream_id. A stream version that " <>
              "nothing checked would be a claim about the stream nobody verified: append " <>
              "with {:stream, id, expected_version} instead"
    end

    {:ok, rows}
  end

  defp apply_condition(repo, rows, {:stream, stream_id, expected})
       when is_binary(stream_id) and is_integer(expected) and expected >= 0 do
    # The condition names the stream and the store numbers it. An entry that names
    # one as well would be overwritten silently, and the stream it meant would never
    # be checked.
    if Enum.any?(rows, &(Map.get(&1, :stream_id) || Map.get(&1, :stream_version))) do
      raise ArgumentError,
            "an entry appended under {:stream, #{inspect(stream_id)}, _} carries its own " <>
              "stream_id or stream_version. The condition names the stream and the store " <>
              "numbers it, so leave both out of the entry"
    end

    current =
      repo.one(
        from(e in Event,
          where: e.stream_id == ^stream_id,
          select: coalesce(max(e.stream_version), 0)
        )
      )

    if current == expected do
      versioned =
        rows
        |> Enum.with_index(expected + 1)
        |> Enum.map(fn {row, version} ->
          Map.merge(row, %{stream_id: stream_id, stream_version: version})
        end)

      {:ok, versioned}
    else
      {:error, :wrong_expected_version}
    end
  end

  # An entry becomes the row `insert_all/3` needs: only the writable columns, and
  # the defaults a schema insert would have filled in.
  @spec row!(map()) :: map()
  defp row!(entry) when is_map(entry) do
    case Map.keys(entry) -- @writable do
      [] ->
        :ok

      extra ->
        raise ArgumentError,
              "cannot append #{inspect(extra)}: the store assigns position and recorded_at, " <>
                "and an entry holds only #{inspect(@writable)}"
    end

    Map.merge(
      %{id: Ecto.UUID.generate(), schema_version: 1, tags: [], payload: %{}, metadata: %{}},
      entry
    )
  end

  @spec in_transaction!(module()) :: :ok
  defp in_transaction!(repo) do
    if repo.in_transaction?() do
      :ok
    else
      raise ArgumentError,
            "EhOsContract.Store appends inside the caller's transaction. Outside one, the " <>
              "append lock is released at the end of the statement that took it, and it " <>
              "orders nothing."
    end
  end
end
