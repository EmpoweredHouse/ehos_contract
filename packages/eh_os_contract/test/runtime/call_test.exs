defmodule EhOsContract.CallTest do
  @moduledoc """
  Plan E12d: `EhOsContract.call/3`, the one way in for data from outside — a
  capability's name, the data as sent, a credential — which asks whether the caller
  may before it says what is wrong with what was sent. `EhOsContract.Plug` is one
  door onto it, tested in `plug_test.exs`; these call it as any other door would.
  """

  use EhOsContract.DataCase, async: false

  alias EhOsContract.{Actor, Receipt}

  @query "dispatch_rig.balances_for_branch"

  @clerk Actor.credential(
           "u-1",
           ["dispatch_rig.open_account", "dispatch_rig.deposit", @query],
           %{@query => %{"branch_id" => ["b-7"]}}
         )

  @stranger Actor.credential("u-9", ["dispatch_rig.open_account"])

  setup do
    {:ok, _} =
      EhOsContract.call(
        {:command, "dispatch_rig.open_account"},
        %{"account_id" => "a-1", "branch_id" => "b-7"},
        actor: @clerk
      )

    :ok
  end

  defp deposit(input, actor, opts \\ []),
    do: EhOsContract.call({:command, "dispatch_rig.deposit"}, input, [actor: actor] ++ opts)

  test "a command goes through dispatch under its capability, with the caller's key" do
    assert {:ok, %Receipt{duplicate: false, positions: [position]}} =
             deposit(%{"account_id" => "a-1", "amount" => 40}, @clerk, idempotency_key: "req-1")

    assert {:ok, %Receipt{duplicate: true, positions: [^position]}} =
             deposit(%{"account_id" => "a-1", "amount" => 40}, @clerk, idempotency_key: "req-1")
  end

  test "a recording and a query are taken the same way, a query's values as text" do
    auditor = Actor.credential("u-2", ["dispatch_rig.balance_confirmed"])

    assert {:ok, %Receipt{}} =
             EhOsContract.call(
               {:record, "dispatch_rig.balance_confirmed"},
               %{"account_id" => "a-1"},
               actor: auditor
             )

    assert {:ok, [%{account_id: "a-1"}]} =
             EhOsContract.call({:query, @query}, %{"branch_id" => "b-7"}, actor: @clerk)
  end

  test "a name no contract declares as that kind is not found, nor is <name>.subscribe" do
    assert EhOsContract.call({:record, "dispatch_rig.deposit"}, %{}, actor: @clerk) ==
             {:error, :not_found}

    assert EhOsContract.call({:command, "bus_rig_shop.order.placed.subscribe"}, %{},
             actor: @clerk
           ) ==
             {:error, :not_found}

    # A door serves the contracts it is given, and only those.
    assert deposit(%{"account_id" => "a-1", "amount" => 1}, @clerk,
             contracts: [DispatchRig.Transfer]
           ) == {:error, :not_found}
  end

  test "without a credential's actor nothing runs: a :system actor dispatches structs" do
    assert deposit(%{"account_id" => "a-1", "amount" => 1}, nil) == {:error, :no_actor}

    assert deposit(%{"account_id" => "a-1", "amount" => 1}, Actor.system(:teller)) ==
             {:error, :no_actor}
  end

  test "a correlation id is a UUID's text, not any sixteen bytes" do
    assert deposit(%{"account_id" => "a-1", "amount" => 1}, @clerk,
             correlation_id: "0123456789abcdef"
           ) == {:error, :correlation_id_is_not_a_uuid}

    assert {:ok, %Receipt{}} =
             deposit(%{"account_id" => "a-1", "amount" => 1}, @clerk,
               correlation_id: Ecto.UUID.generate()
             )
  end

  test "a query reads its writes through call/3 as through query/3" do
    # Over a read model projected after the transaction, which nothing drains here.
    auditor = Actor.credential("u-3", ["dispatch_rig.lines_of"])

    assert EhOsContract.call({:query, "dispatch_rig.lines_of"}, %{"account_id" => "a-1"},
             actor: auditor,
             min_position: 1_000_000,
             wait: 0
           ) == {:error, :not_caught_up}
  end

  test "options may come as a map, as dispatch/3 takes them" do
    assert {:ok, %Receipt{}} =
             EhOsContract.call(
               {:command, "dispatch_rig.deposit"},
               %{"account_id" => "a-1", "amount" => 1},
               %{actor: @clerk}
             )
  end

  describe "whether the caller may is answered first" do
    test "not an object, fields that do not decode, a correlation that is not a UUID" do
      for {input, opts, problem} <- [
            {[1, 2], [], :not_an_object},
            {%{"account_id" => "a-1", "amount" => "a lot"}, [], {:invalid, [amount: :type]}},
            {%{"account_id" => "a-1", "amount" => 1}, [correlation_id: "nope"],
             :correlation_id_is_not_a_uuid}
          ] do
        assert deposit(input, @stranger, opts) == {:error, :missing_capability}
        assert deposit(input, @clerk, opts) == {:error, problem}
      end
    end

    test "a scoped command that does not decode is asked with the scope value as sent" do
      move = "dispatch_rig.move_account"
      clerk = Actor.credential("u-1", [move], %{move => %{"branch_id" => ["b-7"]}})
      input = %{"account_id" => 7, "branch_id" => "b-9"}

      assert EhOsContract.call({:command, move}, input, actor: clerk) ==
               {:error, :outside_scope}

      # The control: within the grant, what is wrong with it is the answer.
      assert EhOsContract.call({:command, move}, %{input | "branch_id" => "b-7"}, actor: clerk) ==
               {:error, {:invalid, [account_id: :type]}}
    end
  end
end
