defmodule EhOsContract.PlugTest do
  @moduledoc """
  The model's commands and queries over HTTP (v2 §16, D10): the same checks as a
  function call, under the capability's name, with the actor another plug built.
  """

  use EhOsContract.DataCase, async: false

  import Plug.Conn
  import Plug.Test

  alias EhOsContract.{Actor, Event}

  @opts EhOsContract.Plug.init(contracts: [DispatchRig.Ledger])
  @query "dispatch_rig.balances_for_branch"

  @clerk Actor.credential(
           "u-1",
           ["dispatch_rig.open_account", "dispatch_rig.deposit", "dispatch_rig.withdraw", @query],
           %{@query => %{"branch_id" => ["b-7"]}}
         )

  defp call(conn, actor \\ @clerk) do
    conn
    |> assign(:eh_os_contract_actor, actor)
    |> EhOsContract.Plug.call(@opts)
  end

  defp json(conn), do: Jason.decode!(conn.resp_body)

  defp post(path, body),
    do:
      conn(:post, path, Jason.encode!(body)) |> put_req_header("content-type", "application/json")

  setup do
    conn =
      call(post("/commands/dispatch_rig.open_account", %{account_id: "a-1", branch_id: "b-7"}))

    assert conn.status == 200
    :ok
  end

  test "a command is dispatched under its capability, and the receipt comes back" do
    conn =
      post("/commands/dispatch_rig.deposit", %{account_id: "a-1", amount: 40})
      |> put_req_header("idempotency-key", "req-1")
      |> call()

    assert conn.status == 200
    body = json(conn)
    assert body["duplicate"] == false
    assert [%{"type" => "ledger.deposited", "position" => position}] = body["events"]
    assert body["positions"] == [position]

    again =
      post("/commands/dispatch_rig.deposit", %{account_id: "a-1", amount: 40})
      |> put_req_header("idempotency-key", "req-1")
      |> call()

    assert json(again)["duplicate"] == true
    assert json(again)["positions"] == [position]
  end

  test "each outcome has its status, and no body carries a value the caller did not send" do
    rejected = call(post("/commands/dispatch_rig.withdraw", %{account_id: "a-1", amount: 5}))
    assert {rejected.status, json(rejected)} == {422, %{"rejected" => "balance_never_negative"}}

    invalid = call(post("/commands/dispatch_rig.deposit", %{account_id: "a-1", amount: "a lot"}))
    assert {invalid.status, json(invalid)} == {422, %{"invalid" => %{"amount" => "type"}}}

    refused =
      call(
        post("/commands/dispatch_rig.deposit", %{account_id: "a-1", amount: 1}),
        Actor.credential("u-2", [])
      )

    assert {refused.status, json(refused)} == {403, %{"refused" => "missing_capability"}}

    unknown = call(post("/commands/dispatch_rig.transfer", %{}))
    assert unknown.status == 404

    # A query's name is not a command's.
    assert call(post("/commands/#{@query}", %{})).status == 404
  end

  test "without a credential's actor the answer is 401, and a :system actor never comes over HTTP" do
    body = %{account_id: "a-1", amount: 1}
    assert call(post("/commands/dispatch_rig.deposit", body), nil).status == 401

    assert call(post("/commands/dispatch_rig.deposit", body), Actor.system(:nightly_import)).status ==
             401

    assert Repo.aggregate(Event, :count) == 1
  end

  test "a query answers the rows the credential grants, and refuses another branch" do
    conn = call(conn(:get, "/queries/#{@query}?branch_id=b-7"))
    assert conn.status == 200

    assert json(conn) == %{
             "rows" => [%{"account_id" => "a-1", "branch_id" => "b-7", "balance" => 0}]
           }

    outside = call(conn(:get, "/queries/#{@query}?branch_id=b-9"))
    assert {outside.status, json(outside)} == {403, %{"refused" => "outside_scope"}}
  end

  test "a correlation id that is not a UUID is refused before anything runs" do
    conn =
      post("/commands/dispatch_rig.deposit", %{account_id: "a-1", amount: 1})
      |> put_req_header("x-correlation-id", "not-a-uuid")
      |> call()

    assert conn.status == 400
    assert Repo.aggregate(Event, :count) == 1
  end
end
