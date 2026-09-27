defmodule EhOsContract.DispatchCommandTest do
  @moduledoc """
  A command to a v2 contract, from its actor to the log (v2 §11), on the invented
  `DispatchRig.Ledger`: who may issue it, what it has to carry, what the decision
  may return, and what is written for each outcome.

  `async: false`: dispatch takes the one append lock, and a sandboxed test holds it
  until the test ends.
  """

  use EhOsContract.DataCase, async: false

  alias DispatchRig.Ledger
  alias DispatchRig.Ledger.Commands.{Deposit, Misbehave, OpenAccount, Withdraw}
  alias DispatchRig.Ledger.Events.{Deposited, Withdrawn}
  alias EhOsContract.{Actor, CommandRecord, Event, Receipt, Rejection}

  @all ~w(open_account deposit withdraw misbehave) |> Enum.map(&"dispatch_rig.#{&1}")

  defp clerk(capabilities \\ @all), do: Actor.credential("u-1", capabilities)

  defp log, do: Repo.all(from(e in Event, order_by: e.position))
  defp rows, do: Repo.all(from(c in CommandRecord, order_by: c.recorded_at))

  defp deposit!(account, amount, opts \\ []) do
    {:ok, receipt} =
      EhOsContract.dispatch(
        Ledger,
        %Deposit{account_id: account, amount: amount},
        Keyword.merge([actor: clerk()], opts)
      )

    receipt
  end

  describe "an accepted command" do
    test "appends to the unit's stream and writes the accepted row" do
      assert {:ok, %Receipt{duplicate: false} = receipt} =
               EhOsContract.dispatch(Ledger, %OpenAccount{account_id: "a-1", branch_id: "b-7"},
                 actor: clerk()
               )

      assert [event] = log()
      assert event.type == "ledger.account_opened"
      assert event.stream_id == "account:a-1"
      assert event.stream_version == 1
      assert event.tags == ["account_id:a-1", "branch_id:b-7"]
      assert event.process == "ledger"
      assert event.instance_id == "ledger|a-1"
      assert event.actor == "actor:u-1"
      assert event.payload == %{"account_id" => "a-1", "branch_id" => "b-7"}
      assert event.contract_version == EhOsContract.Model.fetch(Ledger).version
      assert event.command_id == receipt.command_id
      assert receipt.positions == [event.position]
      assert [%{__meta__: %{id: id, position: position}}] = receipt.events
      assert {id, position} == {event.id, event.position}

      assert [row] = rows()
      assert row.id == receipt.command_id
      assert row.outcome == "accepted"
      assert row.type == "open_account"
      assert row.issued_by == "actor:u-1"
      assert row.emitted_types == ["ledger.account_opened"]
      assert {row.first_position, row.last_position} == {position, position}
      assert row.instance_id == "ledger|a-1"
    end

    test "the decision sees the stream folded through evolve/2" do
      deposit!("a-1", 100)
      deposit!("a-1", 50)

      assert {:ok, %Receipt{events: [%Withdrawn{amount: 150}]}} =
               EhOsContract.dispatch(Ledger, %Withdraw{account_id: "a-1", amount: 150},
                 actor: clerk()
               )

      assert Enum.map(log(), & &1.stream_version) == [1, 2, 3]

      # Two deposits read, one type recorded.
      assert Enum.map(rows(), & &1.given_types) |> List.last() == ["ledger.deposited"]
    end
  end

  describe "who may issue it" do
    test "a credential without the capability is refused, and nothing is written" do
      assert EhOsContract.dispatch(Ledger, %Deposit{account_id: "a-1", amount: 1},
               actor: clerk(["dispatch_rig.withdraw"])
             ) == {:error, :missing_capability}

      assert log() == []
      assert rows() == []
    end

    test "a :system actor passes where the command names it, and only there" do
      import_actor = Actor.system(:nightly_import)

      assert {:ok, _} =
               EhOsContract.dispatch(Ledger, %Deposit{account_id: "a-1", amount: 1},
                 actor: import_actor
               )

      assert EhOsContract.dispatch(Ledger, %Withdraw{account_id: "a-1", amount: 1},
               actor: import_actor
             ) ==
               {:error, :not_declared}

      # A person's actor passed off as the application's own code.
      assert EhOsContract.dispatch(Ledger, %Withdraw{account_id: "a-1", amount: 1},
               actor: Actor.system(:clerk)
             ) == {:error, :not_declared}

      assert length(log()) == 1
    end

    test "dispatch without an actor is a programming error" do
      assert_raise ArgumentError, ~r/takes `actor:`/, fn ->
        EhOsContract.dispatch(Ledger, %Deposit{account_id: "a-1", amount: 1}, [])
      end
    end
  end

  describe "what it has to carry" do
    test "fields that do not fit their types are refused, by name, and nothing is written" do
      assert EhOsContract.dispatch(Ledger, %Deposit{account_id: "a-1", amount: "100"},
               actor: clerk()
             ) ==
               {:error, {:invalid, [amount: :type]}}

      assert EhOsContract.dispatch(Ledger, %Deposit{account_id: nil, amount: 1}, actor: clerk()) ==
               {:error, {:invalid, [account_id: :required]}}

      assert log() == []
      assert rows() == []
    end
  end

  describe "a rejection" do
    test "appends nothing and writes the rejected row with the invariant" do
      deposit!("a-1", 100)

      assert EhOsContract.dispatch(Ledger, %Withdraw{account_id: "a-1", amount: 150},
               actor: clerk()
             ) ==
               {:error, %Rejection{invariant: :balance_never_negative}}

      assert length(log()) == 1
      assert %{outcome: "rejected", invariant: "balance_never_negative"} = List.last(rows())
    end
  end

  describe "a decision that returns what it does not declare" do
    test "raises, appends nothing, and leaves a failed row" do
      assert_raise ArgumentError, ~r/not among the events it emits: \[:deposited\]/, fn ->
        EhOsContract.dispatch(Ledger, %Misbehave{account_id: "a-1"}, actor: clerk())
      end

      assert log() == []
      assert [%{outcome: "failed", failed_in: "decider", error: "ArgumentError"}] = rows()
    end

    test "an event for another unit raises, since it would be appended to this unit's stream" do
      Process.put(:dispatch_rig_stray, "a-2")

      assert_raise ArgumentError, ~r/for another unit: its account_id is not the command's/, fn ->
        deposit!("a-1", 5)
      end

      assert log() == []
      assert [%{outcome: "failed", failed_in: "decider"}] = rows()
    end

    test "control: the same account takes a declared event" do
      assert %Receipt{events: [%Deposited{amount: 5}]} = deposit!("a-1", 5)
      assert length(log()) == 1
    end
  end

  describe "a conflict" do
    test "is retried when dispatch owns the transaction" do
      Process.put(:dispatch_rig_race, true)

      assert %Receipt{events: [%Deposited{amount: 10}]} = deposit!("a-1", 10)

      # The race's own event rolled back with the attempt that met it.
      assert [%{stream_version: 1, payload: %{"amount" => 10}}] = log()
      assert [%{outcome: "accepted"}] = rows()
    end

    test "is returned inside the caller's transaction, which cannot be replayed" do
      Process.put(:dispatch_rig_race, true)

      assert {:ok, {:error, :conflict}} =
               Repo.transaction(fn ->
                 EhOsContract.dispatch(Ledger, %Deposit{account_id: "a-1", amount: 10},
                   actor: clerk()
                 )
               end)
    end
  end

  describe "an idempotency key" do
    test "accepted once returns the same receipt again, and appends nothing" do
      first = deposit!("a-1", 10, idempotency_key: "k-1")
      again = deposit!("a-1", 10, idempotency_key: "k-1")

      assert again.duplicate
      assert again.command_id == first.command_id
      assert again.positions == first.positions
      assert [%Deposited{amount: 10}] = again.events
      assert length(log()) == 1
      assert length(rows()) == 1
    end

    test "accepted for another command is refused" do
      deposit!("a-1", 10, idempotency_key: "k-1")

      assert EhOsContract.dispatch(Ledger, %Withdraw{account_id: "a-1", amount: 1},
               actor: clerk(),
               idempotency_key: "k-1"
             ) == {:error, :idempotency_key_reused}
    end

    test "a rejected command does not bind its key, so it can be sent again" do
      withdraw = %Withdraw{account_id: "a-1", amount: 10}

      assert {:error, %Rejection{}} =
               EhOsContract.dispatch(Ledger, withdraw, actor: clerk(), idempotency_key: "k-2")

      deposit!("a-1", 10)

      assert {:ok, %Receipt{duplicate: false}} =
               EhOsContract.dispatch(Ledger, withdraw, actor: clerk(), idempotency_key: "k-2")
    end
  end
end
