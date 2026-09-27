defmodule EhOsContract.Store.Suite do
  @moduledoc """
  The tests every `EhOsContract.Store` implementation has to pass, as a module to
  `use` in an ExUnit case:

      defmodule MyApp.StoreTest do
        use ExUnit.Case, async: false
        use EhOsContract.Store.Suite, store: MyApp.Store, repo: MyApp.CommitRepo
      end

  In `lib/` rather than in this package's tests for the reason
  `EhOsContract.ContractExample` is: an implementation written elsewhere has to be
  able to run it, and a module compiled only in this package's test build does not
  exist anywhere else.

  **The repo must commit for real.** The ordering tests run appends in several
  processes at once and check what each can see, which the Ecto sandbox's one
  rolled-back transaction per test cannot show. Migrate the repo with
  `EhOsContract.Migrations`. Rows written here stay, because the log is append-only,
  so every test writes under types and streams of its own and never assumes the log
  is empty. Keep the case `async: false`.

  A refusal is asserted as an `ArgumentError` and nothing more specific. The wording
  belongs to the implementation, and each implementation pins its own.
  """

  @doc false
  defmacro __using__(opts) do
    store = Keyword.fetch!(opts, :store)
    repo = Keyword.fetch!(opts, :repo)

    quote location: :keep do
      require Ecto.Query

      @store unquote(store)
      @repo unquote(repo)

      defp suite_name(tag), do: "store-suite-#{tag}-#{System.unique_integer([:positive])}"

      defp suite_entry(type, attrs \\ %{}) do
        Map.merge(
          %{
            type: type,
            contract: "EhOsContract.Store.Suite",
            contract_version: "suite",
            correlation_id: Ecto.UUID.generate(),
            actor: "system",
            occurred_at: DateTime.utc_now(),
            payload: %{}
          },
          attrs
        )
      end

      defp suite_append(entries, condition) do
        {:ok, result} = @repo.transaction(fn -> @store.append(@repo, entries, condition) end)
        result
      end

      describe "#{inspect(@store)}: appending" do
        test "returns the events in entry order, with increasing positions" do
          type = suite_name("order")
          ids = for _ <- 1..3, do: Ecto.UUID.generate()

          assert {:ok, events} = suite_append(Enum.map(ids, &suite_entry(type, %{id: &1})), :none)

          assert Enum.map(events, & &1.id) == ids
          positions = Enum.map(events, & &1.position)
          assert positions == Enum.sort(positions) and length(Enum.uniq(positions)) == 3
          assert Enum.all?(events, &match?(%DateTime{}, &1.recorded_at))
        end

        test "an empty list appends nothing" do
          assert {:ok, []} = suite_append([], :none)
        end

        test "refuses to run outside a transaction" do
          assert_raise ArgumentError, fn ->
            @store.append(@repo, [suite_entry(suite_name("outside"))], :none)
          end
        end

        test "writes an event's runs with it: the home run, and each run it is included in once" do
          type = suite_name("runs")

          assert {:ok, [with_runs, without]} =
                   suite_append(
                     [
                       suite_entry(type, %{
                         process: "home",
                         instance_id: "home|1",
                         runs: [{"other", "other|7"}, {"other", "other|7"}]
                       }),
                       suite_entry(type)
                     ],
                     :none
                   )

          runs = fn event ->
            @repo.all(
              Ecto.Query.from(r in EhOsContract.EventRun,
                where: r.position == ^event.position,
                order_by: r.process,
                select: {r.process, r.instance_id}
              )
            )
          end

          assert runs.(with_runs) == [{"home", "home|1"}, {"other", "other|7"}]
          assert runs.(without) == []
        end

        test "refuses a stream id under :none, whose version nothing would check" do
          assert_raise ArgumentError, fn ->
            suite_append([suite_entry(suite_name("unchecked"), %{stream_id: "s"})], :none)
          end
        end
      end

      describe "#{inspect(@store)}: streams" do
        test "a new stream starts at version 1, and a read returns it in version order" do
          stream = suite_name("stream")
          type = suite_name("stream-type")

          assert {:ok, [_, _]} =
                   suite_append([suite_entry(type), suite_entry(type)], {:stream, stream, 0})

          assert {:ok, [third]} = suite_append([suite_entry(type)], {:stream, stream, 2})

          assert third.stream_version == 3
          assert Enum.map(@store.read_stream(@repo, stream, 0), & &1.stream_version) == [1, 2, 3]
          assert Enum.map(@store.read_stream(@repo, stream, 2), & &1.stream_version) == [3]
        end

        test "an entry that names its own stream is refused; the condition names it" do
          stream = suite_name("named")
          type = suite_name("named-type")

          assert_raise ArgumentError, fn ->
            suite_append(
              [suite_entry(type, %{stream_id: suite_name("other")})],
              {:stream, stream, 0}
            )
          end

          assert_raise ArgumentError, fn ->
            suite_append([suite_entry(type, %{stream_version: 7})], {:stream, stream, 0})
          end

          assert @store.read_stream(@repo, stream, 0) == []
        end

        test "a stale expected version is refused and writes nothing; the right one is accepted" do
          stream = suite_name("conflict")
          type = suite_name("conflict-type")
          {:ok, _} = suite_append([suite_entry(type)], {:stream, stream, 0})

          assert {:error, :wrong_expected_version} =
                   suite_append([suite_entry(type)], {:stream, stream, 0})

          assert {:error, :wrong_expected_version} =
                   suite_append([suite_entry(type)], {:stream, stream, 5})

          assert length(@store.read_stream(@repo, stream, 0)) == 1

          # The control: the version the stream is actually at.
          assert {:ok, [second]} = suite_append([suite_entry(type)], {:stream, stream, 1})
          assert second.stream_version == 2
        end

        test "fifty concurrent appenders to one stream end with versions 1..50 and no gap" do
          stream = suite_name("race")
          type = suite_name("race-type")

          append_until_accepted = fn append_until_accepted ->
            result =
              @repo.transaction(fn ->
                expected = @store.read_stream(@repo, stream, 0) |> length()

                case @store.append(@repo, [suite_entry(type)], {:stream, stream, expected}) do
                  {:ok, [event]} -> event
                  {:error, :wrong_expected_version} -> @repo.rollback(:conflict)
                end
              end)

            case result do
              {:ok, event} -> event
              {:error, :conflict} -> append_until_accepted.(append_until_accepted)
            end
          end

          1..50
          |> Enum.map(fn _ ->
            Task.async(fn -> append_until_accepted.(append_until_accepted) end)
          end)
          |> Enum.each(&Task.await(&1, 60_000))

          events = @store.read_stream(@repo, stream, 0)
          assert Enum.map(events, & &1.stream_version) == Enum.to_list(1..50)

          positions = Enum.map(events, & &1.position)
          assert positions == Enum.sort(positions), "versions and positions disagree on the order"
        end
      end

      describe "#{inspect(@store)}: consistency boundaries" do
        test "read_query returns what matches, types OR-ed and tags AND-ed, and the head it read to" do
          [a, b, c] = [suite_name("q-a"), suite_name("q-b"), suite_name("q-c")]
          payer = suite_name("payer")

          {:ok, [a1, _a_other, b1, _c1]} =
            suite_append(
              [
                suite_entry(a, %{tags: ["payer:#{payer}", "period:7"]}),
                suite_entry(a, %{tags: ["payer:#{payer}", "period:8"]}),
                suite_entry(b, %{tags: ["payer:#{payer}"]}),
                suite_entry(c, %{tags: ["payer:#{payer}", "period:7"]})
              ],
              :none
            )

          query = [
            %{types: [a], tags: ["payer:#{payer}", "period:7"]},
            %{types: [b], tags: []}
          ]

          {events, head} = @store.read_query(@repo, query)

          assert Enum.map(events, & &1.id) == [a1.id, b1.id]
          assert head >= b1.position
        end

        test "an append under the head it read goes in without a stream" do
          type = suite_name("dcb-ok")
          query = [%{types: [type], tags: ["period:1"]}]
          {[], head} = @store.read_query(@repo, query)

          assert {:ok, [event]} =
                   suite_append([suite_entry(type, %{tags: ["period:1"]})], {:dcb, query, head})

          assert event.stream_id == nil and event.stream_version == nil
        end

        test "an event matching the query appended after the head fails the append, and nothing is written" do
          type = suite_name("dcb-moved")
          query = [%{types: [type], tags: ["period:1"]}]
          {[], head} = @store.read_query(@repo, query)

          {:ok, [_]} = suite_append([suite_entry(type, %{tags: ["period:1"]})], :none)
          marker = suite_name("never-written")

          assert {:error, :condition_failed} =
                   suite_append(
                     [suite_entry(type, %{tags: ["period:1", marker]})],
                     {:dcb, query, head}
                   )

          assert {[_one], _} = @store.read_query(@repo, query)
          assert {[], _} = @store.read_query(@repo, [%{types: [type], tags: [marker]}])
        end

        test "an event outside the query appended after the head does not fail it" do
          type = suite_name("dcb-other")
          query = [%{types: [type], tags: ["period:1"]}]
          {[], head} = @store.read_query(@repo, query)

          # The control for the test before: the same type under another tag, and
          # another type under the same tag, are both outside the boundary.
          {:ok, [_, _]} =
            suite_append(
              [
                suite_entry(type, %{tags: ["period:2"]}),
                suite_entry(suite_name("dcb-unrelated"), %{tags: ["period:1"]})
              ],
              :none
            )

          assert {:ok, [_]} =
                   suite_append([suite_entry(type, %{tags: ["period:1"]})], {:dcb, query, head})
        end

        test "a stream on an entry, or an empty query, is refused" do
          type = suite_name("dcb-refused")

          assert_raise ArgumentError, fn ->
            suite_append(
              [suite_entry(type, %{stream_id: "s"})],
              {:dcb, [%{types: [type], tags: []}], 0}
            )
          end

          assert_raise ArgumentError, fn -> suite_append([suite_entry(type)], {:dcb, [], 0}) end
          assert_raise ArgumentError, fn -> @store.read_query(@repo, [%{types: [], tags: []}]) end
        end

        test "two appenders that read the same boundary: exactly one goes in" do
          type = suite_name("dcb-race")
          query = [%{types: [type], tags: ["period:1"]}]
          parent = self()

          appender = fn ->
            @repo.transaction(fn ->
              {_, head} = @store.read_query(@repo, query)
              send(parent, {:read, self()})
              receive do: (:append -> :ok)

              case @store.append(
                     @repo,
                     [suite_entry(type, %{tags: ["period:1"]})],
                     {:dcb, query, head}
                   ) do
                {:ok, [_]} -> :appended
                {:error, :condition_failed} -> @repo.rollback(:condition_failed)
              end
            end)
          end

          tasks = for _ <- 1..2, do: Task.async(appender)

          readers =
            for _ <- tasks do
              assert_receive {:read, pid}, 5_000
              pid
            end

          Enum.each(readers, &send(&1, :append))

          results = tasks |> Enum.map(&Task.await(&1, 10_000)) |> Enum.sort()
          assert results == [{:error, :condition_failed}, {:ok, :appended}]
          assert {[_one], _} = @store.read_query(@repo, query)
        end
      end

      describe "#{inspect(@store)}: reading in position order" do
        test "read_all returns what follows a position, filtered by type, up to a limit" do
          [a, b] = [suite_name("read-a"), suite_name("read-b")]

          {:ok, [a1, _b1, a2]} =
            suite_append([suite_entry(a), suite_entry(b), suite_entry(a)], :none)

          assert Enum.map(@store.read_all(@repo, 0, 10, [a]), & &1.id) == [a1.id, a2.id]
          assert Enum.map(@store.read_all(@repo, a1.position, 10, [a]), & &1.id) == [a2.id]
          assert length(@store.read_all(@repo, 0, 2, [a, b])) == 2
        end

        test "an append waits for an earlier one to commit, so a reader after a checkpoint misses nothing" do
          # Without serialised appends this is the defect of v2 §10.2: the second
          # transaction gets the higher position, commits first, and a reader moves
          # its checkpoint past the lower position before that position is visible.
          types = [suite_name("first"), suite_name("second")]
          [first_type, second_type] = types
          parent = self()

          holder =
            Task.async(fn ->
              @repo.transaction(fn ->
                {:ok, [first]} = @store.append(@repo, [suite_entry(first_type)], :none)
                send(parent, {:appended, first})
                receive do: (:commit -> first)
              end)
            end)

          assert_receive {:appended, first}, 5_000

          waiter =
            Task.async(fn ->
              @repo.transaction(fn ->
                {:ok, [second]} = @store.append(@repo, [suite_entry(second_type)], :none)
                second
              end)
            end)

          refute Task.yield(waiter, 300), "the second append did not wait for the first to commit"
          assert @store.read_all(@repo, 0, 10, types) == []

          send(holder.pid, :commit)
          assert {:ok, _} = Task.await(holder)
          assert {:ok, second} = Task.await(waiter)

          assert second.position > first.position
          assert Enum.map(@store.read_all(@repo, 0, 10, types), & &1.id) == [first.id, second.id]
        end
      end
    end
  end
end
