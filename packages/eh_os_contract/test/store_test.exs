defmodule EhOsContract.StoreTest do
  @moduledoc """
  v2 plan, E2: `EhOsContract.Store.Postgres` against `EhOsContract.Store.Suite`, on a
  database whose transactions commit (`EhOsContract.CommitRepo`), plus what only
  this implementation promises.
  """

  use ExUnit.Case, async: false
  use EhOsContract.Store.Suite, store: EhOsContract.Store.Postgres, repo: EhOsContract.CommitRepo

  alias EhOsContract.CommitRepo, as: Repo
  alias EhOsContract.Store.Postgres

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
          INSERT INTO eh_os_contract_events
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
    assert EhOsContract.Store.impl() == Postgres
  end
end
