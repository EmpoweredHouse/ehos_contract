defmodule EhosContract.SchemaVersionTest do
  @moduledoc """
  Plan W1: a row of the log says which version of its event's fields it was written
  with, and code that declares an older version refuses it rather than misread it.
  A command whose stream holds one is refused; a subscription, a relay and an effect
  wait at it without counting an attempt, so a node not yet upgraded during a
  rolling deploy stops nothing for good.

  The newer rows are appended here as newer code would write them: version 9 of an
  event the invented rigs declare at 1 or 2. `LifecycleRig.Visits` declares
  `:note_added` at version 2.
  """

  use EhosContract.DataCase, async: false

  # Waiting logs a warning, which is the point of some of these tests.
  @moduletag :capture_log

  alias EhosContract.{
    Actor,
    Bus,
    CommandRecord,
    Consumer,
    EffectJob,
    Event,
    Implementations,
    Model,
    NewerSchemaError,
    Store,
    Subscription,
    SubscriptionRecord,
    Testing
  }

  alias LifecycleRig.Visits
  alias LifecycleRig.Visits.Commands.{AddNote, BookVisit}
  alias LifecycleRig.Visits.Events.NoteAdded

  @visit "visit-1"

  defp reception,
    do: Actor.credential("u-reception", ~w(lifecycle_rig.book_visit lifecycle_rig.add_note))

  defp issue(module),
    do: EhosContract.dispatch(Visits, struct(module, visit_id: @visit), actor: reception())

  defp log(stream),
    do: Repo.all(from(e in Event, where: e.stream_id == ^stream, order_by: e.position))

  defp type(contract, event),
    do: Enum.find(Model.fetch(contract).events, &(&1.name == event)).type

  # A row as code declaring version 9 of `event` would append it, at the head of
  # `stream`, which already holds `held` events.
  defp newer!(contract, event, {stream, held}, attrs \\ %{}) do
    entry =
      Map.merge(
        %{
          type: type(contract, event),
          schema_version: 9,
          contract: EhosContract.Model.fetch(contract).id,
          contract_version: Model.fetch(contract).version,
          correlation_id: Ecto.UUID.generate(),
          actor: "newer-code",
          occurred_at: DateTime.utc_now(),
          payload: %{}
        },
        attrs
      )

    {:ok, [row]} =
      Repo.transaction(fn ->
        {:ok, rows} = Store.append(Repo, [entry], {:stream, stream, held})
        rows
      end)

    row
  end

  test "each row carries the schema version its event declares" do
    assert {:ok, _} = issue(BookVisit)
    assert {:ok, _} = issue(AddNote)

    assert [{"lifecycle_rig.visits.booked", 1}, {"lifecycle_rig.visits.note_added", 2}] =
             Enum.map(log("visit:#{@visit}"), &{&1.type, &1.schema_version})
  end

  test "a row written with a newer version than the code declares is refused; control: its own" do
    assert {:ok, _} = issue(BookVisit)
    assert {:ok, _} = issue(AddNote)
    [_booked, note] = log("visit:#{@visit}")

    assert %NoteAdded{visit_id: @visit} = Consumer.decode!(note)

    error = assert_raise NewerSchemaError, fn -> Consumer.decode!(%{note | schema_version: 3}) end

    assert Exception.message(error) ==
             "lifecycle_rig.visits holds \"lifecycle_rig.visits.note_added\" at position #{note.position} " <>
               "written with schema version 3, newer than the 2 this code declares: the code " <>
               "reading it is older than the code that wrote it"
  end

  test "a command whose stream holds a newer row is refused, and appends nothing" do
    assert {:ok, _} = issue(BookVisit)

    newer!(Visits, :note_added, {"visit:#{@visit}", 1}, %{payload: %{"visit_id" => @visit}})

    assert_raise NewerSchemaError, fn -> issue(AddNote) end

    assert ["lifecycle_rig.visits.booked", "lifecycle_rig.visits.note_added"] =
             Enum.map(log("visit:#{@visit}"), & &1.type)

    assert [%{outcome: "failed", error: "EhosContract.NewerSchemaError"}] =
             Repo.all(from(c in CommandRecord, where: c.outcome == "failed"))
  end

  test "a policy waits at a newer row: nothing moves and no attempt is counted" do
    flag = "dispatch_rig.ledger:policy:flag_large_withdrawal"
    Testing.drain(only: flag)
    before = Repo.get!(SubscriptionRecord, flag).position

    newer = newer!(DispatchRig.Ledger, :withdrawn, {"account:a-9", 0})

    for _ <- 1..4 do
      assert {:waiting, position} = Subscription.step(Repo, Implementations.consumer(flag))
      assert position == newer.position
    end

    assert %SubscriptionRecord{status: "running", attempts: 0, failure: nil, position: ^before} =
             Repo.get!(SubscriptionRecord, flag)

    assert %{failing: []} = Testing.drain(only: flag)
  end

  test "a read model applies what comes before a newer row in its batch, and waits at it" do
    lines = "dispatch_rig.ledger:read_model:ledger_lines"
    Subscription.register!(Repo, [Implementations.consumer(lines)])
    Testing.drain(only: lines)
    before = Repo.get!(SubscriptionRecord, lines).position

    clerk = Actor.credential("u-1", ~w(dispatch_rig.open_account dispatch_rig.deposit))
    ledger = &EhosContract.dispatch(DispatchRig.Ledger, &1, actor: clerk)

    {:ok, _} =
      ledger.(%DispatchRig.Ledger.Commands.OpenAccount{account_id: "a-1", branch_id: "b-7"})

    {:ok, _} = ledger.(%DispatchRig.Ledger.Commands.Deposit{account_id: "a-1", amount: 10})
    newer = newer!(DispatchRig.Ledger, :withdrawn, {"account:a-9", 0})

    # One batch of 500 holds both; the deposit commits, and the step after waits.
    assert {:applied, 1} = Subscription.step(Repo, Implementations.consumer(lines))

    assert [{_position, 10}] =
             Repo.all(from(l in "dispatch_rig_lines", select: {l.position, l.amount}))

    for _ <- 1..2 do
      assert {:waiting, position} = Subscription.step(Repo, Implementations.consumer(lines))
      assert position == newer.position
    end

    assert %SubscriptionRecord{status: "running", attempts: 0, position: position} =
             Repo.get!(SubscriptionRecord, lines)

    assert before < position and position < newer.position
  end

  test "a process manager waits at a newer row, and keeps no state from it" do
    chase = "dispatch_rig.ledger:process_manager:first_deposit_chase"
    Subscription.register!(Repo, [Implementations.consumer(chase)])
    Testing.drain(only: chase)

    newer = newer!(DispatchRig.Ledger, :account_opened, {"account:a-9", 0})

    assert {:waiting, position} = Subscription.step(Repo, Implementations.consumer(chase))
    assert position == newer.position

    assert %SubscriptionRecord{status: "running", attempts: 0} =
             Repo.get!(SubscriptionRecord, chase)

    assert [] = Repo.all(EhosContract.ProcessManagerRecord)
  end

  test "an effect's backoff counts only the attempts that ran, not the snoozes" do
    # The third real attempt after 40 snoozes backs off as the third after none would,
    # within Oban's jitter, rather than as attempt 43 of 43.
    snoozed = %Oban.Job{attempt: 43, max_attempts: 43}
    fresh = %Oban.Job{attempt: 3, max_attempts: 3}
    assert EffectJob.backoff(snoozed) < 2 * Oban.Worker.backoff(fresh) + 60
    assert Oban.Worker.backoff(snoozed) > 100_000
  end

  test "an effect's job on a newer row is snoozed, which Oban does not count" do
    newer =
      newer!(DispatchRig.Ledger, :account_flagged, {"account:a-9", 0})

    job = %Oban.Job{
      args: %{"effect" => "dispatch_rig.ledger:effect:notify_branch", "event_id" => newer.id}
    }

    assert {:snooze, 30} = EffectJob.perform(job)
  end

  describe "a relay" do
    defmodule TakingBus do
      @moduledoc false
      @behaviour EhosContract.Bus

      @impl true
      def publish(opts, messages) do
        send(Keyword.fetch!(opts, :to), {:published, Enum.map(messages, & &1.name)})
        :ok
      end

      @impl true
      def consumer(_opts, _consumer), do: raise("not consumed from")
    end

    setup do
      previous = Application.get_env(:ehos_contract, :bus)
      Application.put_env(:ehos_contract, :bus, {TakingBus, to: self()})

      on_exit(fn ->
        if previous,
          do: Application.put_env(:ehos_contract, :bus, previous),
          else: Application.delete_env(:ehos_contract, :bus)
      end)
    end

    test "publishes what comes before a newer row, and waits at it" do
      relay = "bus_rig_shop.orders:relay:order_placed"
      Subscription.register!(Repo, [Implementations.consumer(relay)])
      clerk = Actor.credential("u-1", ["bus_rig_shop.place_order"])

      {:ok, _} =
        EhosContract.dispatch(
          BusRig.Orders,
          %BusRig.Orders.Commands.PlaceOrder{order_id: "o-1", total: 120, note: "gift wrap"},
          actor: clerk
        )

      newer = newer!(BusRig.Orders, :placed, {"order:o-9", 0})

      assert {:applied, 1} = Subscription.step(Repo, Implementations.consumer(relay))
      assert_received {:published, ["bus_rig_shop.order_placed.v1"]}

      assert {:waiting, position} = Subscription.step(Repo, Implementations.consumer(relay))
      assert position == newer.position
      refute_received {:published, _}
      assert Repo.get!(SubscriptionRecord, relay).position == newer.position - 1
    end

    test "waits at a newer row, and publishes nothing of it" do
      relay = "bus_rig_shop.orders:relay:order_placed"
      Subscription.register!(Repo, [Implementations.consumer(relay)])
      before = Repo.get!(SubscriptionRecord, relay).position

      newer = newer!(BusRig.Orders, :placed, {"order:o-9", 0})

      assert {:waiting, position} = Subscription.step(Repo, Implementations.consumer(relay))
      assert position == newer.position
      refute_received {:published, _}

      assert %SubscriptionRecord{status: "running", attempts: 0, position: ^before} =
               Repo.get!(SubscriptionRecord, relay)

      assert Bus.adapter() != nil
    end
  end
end
