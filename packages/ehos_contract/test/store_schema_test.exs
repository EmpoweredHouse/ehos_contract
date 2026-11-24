defmodule EhosContract.StoreSchemaTest do
  @moduledoc """
  v2 plan, E2: **what migration V01 makes the database itself refuse or guarantee.**

  Everything here holds for any writer, the store or not, because it lives in the
  table: the log is append-only, every insert takes the append lock, positions are
  handed out by the database in order, and a stream id never comes without a stream
  version. Each refusal has a control beside it that passes, so a test cannot go
  green because nothing works at all.

  Refused statements abort the sandbox transaction. That is why each refusal is the
  last statement of its test.
  """

  use EhosContract.DataCase, async: false

  alias EhosContract.Event

  # Around the store on purpose: what the table refuses, it refuses from any writer.
  defp row(attrs \\ %{}) do
    Repo.insert!(
      struct!(
        Event,
        Map.merge(
          %{
            type: "noted",
            contract: "Fixture",
            contract_version: "v",
            payload: %{"n" => 1},
            actor: Event.system_actor(),
            correlation_id: Ecto.UUID.generate(),
            occurred_at: DateTime.utc_now()
          },
          attrs
        )
      )
    )
  end

  defp advisory_locks_held do
    Repo.query!(
      "SELECT count(*) FROM pg_locks WHERE locktype = 'advisory' AND pid = pg_backend_pid()"
    ).rows
    |> List.first()
    |> List.first()
  end

  describe "append-only" do
    test "an insert is allowed, and the database hands out increasing positions" do
      first = row()
      second = row()

      assert is_integer(first.position)
      assert second.position > first.position
      assert %DateTime{} = second.recorded_at
    end

    test "UPDATE is refused" do
      row()

      error =
        assert_raise Postgrex.Error, fn -> Repo.update_all(Event, set: [actor: "someone"]) end

      assert error.postgres.code == :restrict_violation
      assert error.postgres.message =~ "append-only: UPDATE"
    end

    test "DELETE is refused" do
      row()
      error = assert_raise Postgrex.Error, fn -> Repo.delete_all(Event) end
      assert error.postgres.message =~ "append-only: DELETE"
    end

    test "TRUNCATE is refused" do
      error =
        assert_raise Postgrex.Error, fn -> Repo.query!("TRUNCATE ehos_contract_events") end

      assert error.postgres.message =~ "append-only: TRUNCATE"
    end

    test "the tables beside it are not append-only" do
      assert {0, _} = Repo.delete_all(EhosContract.Deployment)
      assert {0, _} = Repo.update_all(EhosContract.Deployment, set: [events: []])
    end
  end

  describe "the append lock" do
    test "an insert that goes around the store takes it anyway, for the rest of the transaction" do
      assert advisory_locks_held() == 0
      row()
      assert advisory_locks_held() == 1
      row()
      assert advisory_locks_held() == 1, "the lock is re-entrant, not taken twice"
    end

    test "the store's function takes the same lock" do
      Repo.query!("SELECT ehos_contract_append_lock()")
      assert advisory_locks_held() == 1
      row()
      assert advisory_locks_held() == 1
    end
  end

  describe "streams" do
    test "a stream id with its version is accepted" do
      assert %{stream_id: "case:c-1", stream_version: 1} =
               row(%{stream_id: "case:c-1", stream_version: 1})
    end

    test "a stream id without a version is refused" do
      error = assert_raise Ecto.ConstraintError, fn -> row(%{stream_id: "case:c-1"}) end
      assert error.constraint == "ehos_contract_events_stream_pair"
    end

    test "one stream cannot hold the same version twice" do
      row(%{stream_id: "case:c-1", stream_version: 1})

      error =
        assert_raise Ecto.ConstraintError, fn ->
          row(%{stream_id: "case:c-1", stream_version: 1})
        end

      assert error.constraint == "ehos_contract_events_stream_index"
    end
  end

  test "a row without an actor is refused" do
    error = assert_raise Postgrex.Error, fn -> row(%{actor: nil}) end
    assert error.postgres.code == :not_null_violation
  end
end
