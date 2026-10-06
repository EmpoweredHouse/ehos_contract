defmodule EhOsContract.UndeclaredTypes do
  @moduledoc """
  The event types the log holds that no contract of the application declares, and a
  warning about them at start-up (plan DD, #175).

  From plan DD's ID3 an event's type is `"<contract id>.<event>"`, and a log written
  before it is not read: an upgrading application resets the engine's schema. One
  that does not is told nothing by the rest of the engine. An aggregate whose stream
  holds such a row raises, but a boundary, a subscription, a read model and the
  conformance report read by declared types and skip the rest silently — a boundary
  allowing one booking per seat would accept a second for a seat booked before.
  The same warning covers an event of a contract the application no longer has.

  It warns and goes on: refusing to start would make removing a contract on purpose
  impossible without rewriting the log.

  The log's distinct types are read by walking the `(type, position)` index once per
  type, not by reading every row, so the check costs the number of types, not the
  length of the log.
  """

  require Logger

  @doc """
  The types `repo`'s log holds that are not among `declared`, in Elixir's order. The
  engine's own types — an erasure, a timer's firing — are always declared.
  """
  @spec undeclared(module(), [String.t()]) :: [String.t()]
  def undeclared(repo, declared) do
    known = MapSet.new(declared ++ engine_types())

    repo
    |> types()
    |> Enum.reject(&MapSet.member?(known, &1))
    |> Enum.sort()
  end

  # At most this many types are named in the warning, then how many more there are.
  @named 20

  @doc """
  Logs a warning naming the types `undeclared/2` finds for the application's
  contracts, and returns them. Called once, at start-up. A failure to read the log —
  a missing table, a timeout — is logged and returns `[]`: the check never stops a
  start.
  """
  @spec warn(module(), [map()]) :: [String.t()]
  def warn(repo, models) do
    declared = for model <- models, event <- model.events, event.type != nil, do: event.type

    repo |> undeclared(declared) |> report()
  rescue
    error ->
      Logger.warning(
        "EhOsContract: could not check the event log for undeclared types, and goes on: " <>
          Exception.message(error)
      )

      []
  end

  @doc """
  Logs the start-up warning for `types`, the undeclared types `undeclared/2` found,
  and returns them; logs nothing for none.
  """
  @spec report([String.t()]) :: [String.t()]
  def report([]), do: []

  def report(types) do
    Logger.warning(
      "EhOsContract: the event log holds #{length(types)} type(s) no contract of this " <>
        "application declares: #{named(types)}. Those events are not read: a boundary, a " <>
        "subscription, a read model and the report skip them, and an aggregate whose " <>
        "stream holds one raises. A contract removed on purpose leaves its history so, " <>
        "and a node on older code during a rolling deploy sees the newer node's types so. " <>
        "A log written before event types became \"<contract id>.<event>\" (plan DD, ID3) " <>
        "is read by no contract at all: the CHANGELOG says to reset the engine's schema " <>
        "(EhOsContract.Migrations.down/up), which deletes every event it holds, so only " <>
        "when none of them is worth keeping."
    )

    types
  end

  defp named(types) when length(types) <= @named, do: Enum.join(types, ", ")

  defp named(types),
    do: Enum.join(Enum.take(types, @named), ", ") <> " and #{length(types) - @named} more"

  defp engine_types,
    do: [EhOsContract.Personal.erased_type(), EhOsContract.ProcessManager.elapsed()]

  # A loose index scan: the smallest type, then the smallest greater than the last,
  # each one step down the `(type, position)` index.
  defp types(repo) do
    %{rows: rows} =
      repo.query!(
        """
        WITH RECURSIVE t(type) AS (
          SELECT min(type) FROM eh_os_contract_events
          UNION ALL
          SELECT (SELECT min(e.type) FROM eh_os_contract_events e WHERE e.type > t.type)
          FROM t WHERE t.type IS NOT NULL
        )
        SELECT type FROM t WHERE type IS NOT NULL
        """,
        [],
        log: false
      )

    for [type] <- rows, do: type
  end
end
