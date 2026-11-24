defmodule EhosContract.UnstorableBytesTest do
  @moduledoc """
  Request bytes the log's tables cannot hold — a NUL in a text field (jsonb refuses
  `\\u0000`), invalid UTF-8 (a text column refuses it, and JSON cannot carry it), an
  idempotency key outside printable ASCII — are a refusal of the request, never an
  exception: the class #66 closes for the decisions of `ehos_contract_auth`, here in
  the engine.
  """

  use EhosContract.DataCase, async: false

  import Plug.Conn
  import Plug.Test

  alias EhosContract.{Actor, CommandRecord, Event}

  @opts EhosContract.Plug.init(contracts: [DispatchRig.Ledger, DispatchRig.Transfer])

  @clerk Actor.credential("u-1", ["dispatch_rig.open_account", "dispatch_rig.deposit"])

  defp http(path, body, headers) do
    headers
    |> Enum.reduce(
      conn(:post, path, Jason.encode!(body))
      |> put_req_header("content-type", "application/json"),
      fn {name, value}, conn -> put_req_header(conn, name, value) end
    )
    |> assign(:ehos_contract_actor, @clerk)
    |> EhosContract.Plug.call(@opts)
  end

  setup do
    {:ok, _} =
      EhosContract.call(
        {:command, "dispatch_rig.open_account"},
        %{"account_id" => "a-1", "branch_id" => "b-7"},
        actor: @clerk
      )

    :ok
  end

  test "over HTTP, a NUL in a text field (JSON's \\u0000) is a 422 naming the field" do
    conn =
      http("/commands/dispatch_rig.open_account", %{account_id: "a-2\u0000", branch_id: "b-7"}, [
        {"idempotency-key", "req-1"}
      ])

    assert {conn.status, Jason.decode!(conn.resp_body)} ==
             {422, %{"invalid" => %{"account_id" => "type"}}}

    assert Repo.aggregate(Event, :count) == 1
  end

  test "from a direct caller, invalid UTF-8 in a text field is {:invalid, problems}" do
    assert EhosContract.call(
             {:command, "dispatch_rig.deposit"},
             %{"account_id" => "a-1" <> <<0xFF>>, "amount" => 1},
             actor: @clerk
           ) == {:error, {:invalid, [account_id: :type]}}

    assert Repo.aggregate(CommandRecord, :count) == 1
  end

  test "over HTTP, an idempotency key outside printable ASCII is a 400" do
    conn =
      http("/commands/dispatch_rig.deposit", %{account_id: "a-1", amount: 1}, [
        {"idempotency-key", "req-" <> <<0xE9>>}
      ])

    assert {conn.status, Jason.decode!(conn.resp_body)} ==
             {400, %{"error" => "idempotency_key_invalid"}}

    assert Repo.aggregate(CommandRecord, :count) == 1
  end

  test "over HTTP, a NUL in a query's parameter (%00) is a 422, not a failed read" do
    auditor = Actor.credential("u-2", ["dispatch_rig.balance_of"])

    conn =
      conn(:get, "/queries/dispatch_rig.balance_of?account_id=a-1%00")
      |> assign(:ehos_contract_actor, auditor)
      |> EhosContract.Plug.call(@opts)

    assert {conn.status, Jason.decode!(conn.resp_body)} ==
             {422, %{"invalid" => %{"account_id" => "type"}}}
  end

  test "a recording's text is held to it, and an empty idempotency-key header is a 400" do
    auditor = Actor.credential("u-2", ["dispatch_rig.balance_confirmed"])

    assert EhosContract.call(
             {:record, "dispatch_rig.balance_confirmed"},
             %{"account_id" => "a-1" <> <<0>>},
             actor: auditor
           ) == {:error, {:invalid, [account_id: :type]}}

    conn =
      http("/commands/dispatch_rig.deposit", %{account_id: "a-1", amount: 1}, [
        {"idempotency-key", ""}
      ])

    assert {conn.status, Jason.decode!(conn.resp_body)} ==
             {400, %{"error" => "idempotency_key_invalid"}}
  end

  test "text inside a list is held to it as at the top" do
    fields = [%{name: :tags, type: {:list, :string}, optional: false}]

    assert EhosContract.Codec.decode(fields, %{"tags" => ["a", "b" <> <<0>>]}, %{}) ==
             {:error, [tags: :type]}

    assert {:ok, %{tags: ["a", "b"]}} =
             EhosContract.Codec.decode(fields, %{"tags" => ["a", "b"]}, %{})
  end

  # The key a reaction is dispatched with keeps its form; only one that names would push past
  # the rule is its digest, so no reaction is ever refused its own key.
  test "a reaction's derived key holds to the rule however long its names are" do
    id = Ecto.UUID.generate()

    assert EhosContract.Consumer.reaction_key(
             :policy,
             "dispatch_rig.ledger",
             :echo_deposit,
             id,
             0
           ) ==
             "policy:dispatch_rig.ledger:echo_deposit:#{id}:0"

    long = String.to_atom(String.duplicate("a", 240))
    key = EhosContract.Consumer.reaction_key(:policy, "dispatch_rig.ledger", long, id, 0)
    assert "policy:sha256:" <> hex = key
    assert byte_size(hex) == 64
    assert EhosContract.Dispatcher.idempotency_key?(key)
  end

  test "open: takes a function, never the codec's own mark that lets any bytes in" do
    fields = [%{name: :name, type: :string, optional: false}]

    assert_raise ArgumentError, ~r/open: takes a function/, fn ->
      EhosContract.Codec.decode(fields, %{"name" => "a" <> <<0>>}, %{}, open: :opened)
    end
  end

  test "a struct the host's code built is held to the same: {:invalid, problems}, not a raise" do
    assert EhosContract.dispatch(
             DispatchRig.Ledger,
             %DispatchRig.Ledger.Commands.Deposit{account_id: "a-1" <> <<0>>, amount: 1},
             actor: @clerk
           ) == {:error, {:invalid, [account_id: :type]}}
  end

  test "an idempotency key is printable ASCII of at most 255 bytes, for a command and a recording" do
    deposit = fn key ->
      EhosContract.call(
        {:command, "dispatch_rig.deposit"},
        %{"account_id" => "a-1", "amount" => 1},
        actor: @clerk,
        idempotency_key: key
      )
    end

    for key <- ["req 1", "req-" <> <<0>>, String.duplicate("k", 256), ""] do
      assert deposit.(key) == {:error, :idempotency_key_invalid}, inspect(key)
    end

    assert {:ok, _} = deposit.(String.duplicate("k", 255))
    assert {:ok, _} = deposit.("req-~!")

    # A reaction's actor is a struct anyone can build, naming a policy the contract declares:
    # its key is held to the rule as well.
    assert EhosContract.dispatch(
             DispatchRig.Ledger,
             %DispatchRig.Ledger.Commands.Deposit{account_id: "a-1", amount: 1},
             actor: Actor.reaction(:policy, :echo_deposit),
             idempotency_key: "policy:" <> <<0>>
           ) == {:error, :idempotency_key_invalid}

    auditor = Actor.credential("u-2", ["dispatch_rig.balance_confirmed"])

    assert EhosContract.call(
             {:record, "dispatch_rig.balance_confirmed"},
             %{"account_id" => "a-1"},
             actor: auditor,
             idempotency_key: "req-" <> <<0xE9>>
           ) == {:error, :idempotency_key_invalid}
  end
end
