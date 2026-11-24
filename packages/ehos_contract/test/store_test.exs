defmodule EhosContract.StoreTest do
  @moduledoc """
  v2 plan, E2: `EhosContract.Store.Postgres` against `EhosContract.Store.Suite`, on a
  database whose transactions commit (`EhosContract.CommitRepo`), plus what only
  this implementation promises.
  """

  use ExUnit.Case, async: false
  use EhosContract.Store.Suite, store: EhosContract.Store.Postgres, repo: EhosContract.CommitRepo

  alias EhosContract.CommitRepo, as: Repo
  alias EhosContract.Store.Postgres

  test "an insert that goes around the store waits for the append lock too" do
    parent = self()
    type = "around-the-store-#{System.unique_integer([:positive])}"

    holder =
      Task.async(fn ->
        Repo.transaction(fn ->
          :ok = Postgres.lock(Repo)
          send(parent, :locked)
          receive do: (:commit -> :ok)
        end)
      end)

    assert_receive :locked, 5_000

    around =
      Task.async(fn ->
        Repo.query!(
          """
          INSERT INTO ehos_contract_events
            (id, type, contract, contract_version, correlation_id, actor, occurred_at)
          VALUES ($1, $2, 'StoreTest', 'v', $3, 'system', now())
          """,
          [Ecto.UUID.bingenerate(), type, Ecto.UUID.bingenerate()]
        )
      end)

    refute Task.yield(around, 300), "a plain INSERT did not wait for the append lock"
    send(holder.pid, :commit)
    Task.await(holder)
    assert %{num_rows: 1} = Task.await(around)
  end

  test "a boundary's conflict check reads the positions after the head, not the history" do
    # The check is the statement the store runs under the lock, captured as it runs
    # and explained with its own parameters. The test table is small enough for the
    # planner to prefer a sequential scan whatever the indexes, so sequential scans
    # are switched off: what is asserted is that an index bounded by position can
    # serve the check, which is what keeps it proportional to what was appended
    # since the read rather than to the log (v2 §10.4).
    type = "explained-#{System.unique_integer([:positive])}"
    query = [%{types: [type], tags: ["period:1"]}]
    parent = self()
    handler = "store-test-explain-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler,
      [:ehos_contract, :commit_repo, :query],
      fn _event, _measurements, %{query: sql, params: params}, _ ->
        if sql =~ "SELECT TRUE" and sql =~ ~s("position" > $1),
          do: send(parent, {:check, sql, params})
      end,
      nil
    )

    try do
      {:ok, {:ok, [_]}} =
        Repo.transaction(fn ->
          {_, head} = Postgres.read_query(Repo, query)
          Postgres.append(Repo, [entry(type)], {:dcb, query, head})
        end)
    after
      :telemetry.detach(handler)
    end

    assert_received {:check, sql, params}

    {:ok, plan} =
      Repo.transaction(fn ->
        Repo.query!("SET LOCAL enable_seqscan = off")
        Repo.query!("EXPLAIN " <> sql, params).rows |> List.flatten() |> Enum.join("\n")
      end)

    refute plan =~ "Seq Scan", plan
    assert plan =~ ~r/Index Cond: .*"position" > /, plan
  end

  defp entry(type) do
    %{
      type: type,
      contract: "StoreTest",
      contract_version: "v",
      tags: ["period:1"],
      correlation_id: Ecto.UUID.generate(),
      actor: "system",
      occurred_at: DateTime.utc_now()
    }
  end

  test "refuses to append under a stricter isolation level than READ COMMITTED" do
    assert {:error, %ArgumentError{message: message}} =
             Repo.transaction(fn ->
               Repo.query!("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ")

               try do
                 Postgres.append(Repo, [%{type: "never-written"}], :none)
               rescue
                 error -> Repo.rollback(error)
               end
             end)

    assert message =~ "only under READ COMMITTED"
  end

  test "its refusals say what to do instead" do
    type = "wording-#{System.unique_integer([:positive])}"

    entry = %{
      type: type,
      contract: "StoreTest",
      contract_version: "v",
      correlation_id: Ecto.UUID.generate(),
      actor: "system",
      occurred_at: DateTime.utc_now()
    }

    assert_raise ArgumentError, ~r/inside the caller's transaction/, fn ->
      Postgres.append(Repo, [entry], :none)
    end

    assert_raise ArgumentError, ~r/condition :none carries a stream_id.*\{:stream, id/s, fn ->
      Repo.transaction(fn -> Postgres.append(Repo, [Map.put(entry, :stream_id, "s")], :none) end)
    end

    assert_raise ArgumentError, ~r/leave both out of the entry/, fn ->
      Repo.transaction(fn ->
        Postgres.append(Repo, [Map.put(entry, :stream_id, "s")], {:stream, "t", 0})
      end)
    end
  end

  test "refuses a column the store assigns" do
    assert_raise ArgumentError, ~r/the store assigns position/, fn ->
      Repo.transaction(fn -> Postgres.append(Repo, [%{type: "t", position: 1}], :none) end)
    end
  end

  test "the store is Postgres unless configured otherwise" do
    assert EhosContract.Store.impl() == Postgres
  end
end
