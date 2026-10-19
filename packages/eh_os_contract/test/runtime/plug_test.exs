defmodule EhOsContract.PlugTest do
  @moduledoc """
  The model's commands, recordings and queries over HTTP (v2 §16, D10): the same checks as a
  function call, under the capability's name, with the actor another plug built.
  """

  use EhOsContract.DataCase, async: false

  import Plug.Conn
  import Plug.Test

  alias EhOsContract.{Actor, Event}

  @opts EhOsContract.Plug.init(contracts: [DispatchRig.Ledger, DispatchRig.Transfer])
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
    assert body["identity"] == %{"account_id" => "a-1"}
    assert [%{"type" => "dispatch_rig.ledger.deposited", "position" => position}] = body["events"]
    assert body["positions"] == [position]

    again =
      post("/commands/dispatch_rig.deposit", %{account_id: "a-1", amount: 40})
      |> put_req_header("idempotency-key", "req-1")
      |> call()

    assert json(again)["duplicate"] == true
    assert json(again)["positions"] == [position]
  end

  # A unit whose identity the library gives exists only once a command made it, so a
  # recording for an identity nobody was given names no unit: 404, not a refusal, which
  # would read as a missing capability.
  test "a recording for a unit no command created answers 404 not_created" do
    opts = EhOsContract.Plug.init(contracts: [BoundaryRig.Waitlist])

    registrar = Actor.credential("u-registrar", ["boundary_rig.place_confirmed"])

    record = fn entry_id ->
      post("/records/boundary_rig.place_confirmed", %{entry_id: entry_id})
      |> assign(:eh_os_contract_actor, registrar)
      |> EhOsContract.Plug.call(opts)
    end

    conn = record.("entry-made-up")
    assert {conn.status, json(conn)} == {404, %{"error" => "not_created"}}
    assert Repo.all(from(e in Event, where: like(e.type, "boundary_rig.waitlist.%"))) == []

    # The control: for an entry a command made, the same recording is appended.
    {:ok, %{identity: %{entry_id: id}}} =
      EhOsContract.dispatch(
        BoundaryRig.Waitlist,
        %BoundaryRig.Waitlist.Commands.JoinWaitlist{
          course_id: "course-math",
          student_id: "student-anna"
        },
        actor: Actor.credential("u-registrar", ["boundary_rig.join_waitlist"]),
        idempotency_key: "join-anna"
      )

    assert record.(id).status == 200
  end

  test "a person's observation is recorded under the event's capability, and not without it" do
    auditor = Actor.credential("u-2", ["dispatch_rig.balance_confirmed"])

    conn = call(post("/records/dispatch_rig.balance_confirmed", %{account_id: "a-1"}), auditor)

    assert conn.status == 200
    assert [%{"type" => "dispatch_rig.ledger.balance_confirmed"}] = json(conn)["events"]

    # The control: the clerk has no capability to record it.
    refused = call(post("/records/dispatch_rig.balance_confirmed", %{account_id: "a-1"}))
    assert {refused.status, json(refused)} == {403, %{"refused" => "missing_capability"}}

    # A command's capability is not a recording's, and the other way round.
    assert call(post("/records/dispatch_rig.deposit", %{account_id: "a-1"})).status == 404

    assert call(post("/commands/dispatch_rig.balance_confirmed", %{account_id: "a-1"}), auditor).status ==
             404
  end

  test "a command that creates its aggregate answers with the identity the library gave it" do
    opts = EhOsContract.Plug.init(contracts: [BoundaryRig.Waitlist])

    registrar =
      Actor.credential("u-registrar", [
        "boundary_rig.join_waitlist",
        "boundary_rig.leave_waitlist"
      ])

    send = fn path, body, key ->
      post(path, body)
      |> put_req_header("idempotency-key", key)
      |> assign(:eh_os_contract_actor, registrar)
      |> EhOsContract.Plug.call(opts)
    end

    joined =
      send.(
        "/commands/boundary_rig.join_waitlist",
        %{course_id: "course-math", student_id: "student-anna"},
        "join-anna"
      )

    assert joined.status == 200
    assert %{"identity" => %{"entry_id" => id}} = json(joined)

    # With it, the client can address the entry it made.
    left = send.("/commands/boundary_rig.leave_waitlist", %{entry_id: id}, "leave-anna")
    assert {left.status, json(left)["identity"]} == {200, %{"entry_id" => id}}

    # Without a key, a retry would make a second entry, so the command is refused.
    unkeyed =
      post("/commands/boundary_rig.join_waitlist", %{course_id: "c", student_id: "s"})
      |> assign(:eh_os_contract_actor, registrar)
      |> EhOsContract.Plug.call(opts)

    assert {unkeyed.status, json(unkeyed)} == {422, %{"error" => "idempotency_key_required"}}
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

  test "without a credential's actor the body is not read: 401 costs no parsing" do
    body = Jason.encode!(%{account_id: "a-1", amount: 1})
    conn = call(conn(:post, "/commands/dispatch_rig.deposit", body), nil)

    assert conn.status == 401
    assert {:ok, ^body, _conn} = read_body(conn)
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

  test "a list query parameter preserves every repeated form key" do
    fields = [%{name: :account_ids, type: {:list, :id}}]
    conn = conn(:get, "/?account_ids=a-1&account_ids=a-2")

    {_conn, input} = EhOsContract.Plug.decode_query_params(conn, fields, %{})

    assert input == %{"account_ids" => ["a-1", "a-2"]}
  end

  test "a scoped command is refused for a branch the credential does not grant" do
    move = "dispatch_rig.move_account"
    clerk = Actor.credential("u-1", [move], %{move => %{"branch_id" => ["b-7"]}})

    outside = call(post("/commands/#{move}", %{account_id: "a-1", branch_id: "b-9"}), clerk)
    assert {outside.status, json(outside)} == {403, %{"refused" => "outside_scope"}}

    within = call(post("/commands/#{move}", %{account_id: "a-1", branch_id: "b-7"}), clerk)
    assert within.status == 200
  end

  describe "whether the caller may is answered before what is wrong with the request" do
    # Tells the test process about every question, so a request asked twice or not at
    # all shows. The plug runs in the test process under `Plug.Test`.
    defmodule Counting do
      @moduledoc false
      @behaviour EhOsContract.Authorizer

      @impl true
      def authorize(actor, request) do
        send(self(), {:asked, request.capability, request.scope})
        EhOsContract.Authorizer.check(actor, request)
      end
    end

    setup do
      previous = Application.get_env(:eh_os_contract, :authorizer)
      Application.put_env(:eh_os_contract, :authorizer, Counting)

      on_exit(fn ->
        if previous,
          do: Application.put_env(:eh_os_contract, :authorizer, previous),
          else: Application.delete_env(:eh_os_contract, :authorizer)
      end)
    end

    defp asked do
      receive do
        {:asked, capability, scope} -> [{capability, scope} | asked()]
      after
        0 -> []
      end
    end

    test "a caller without the capability is refused, whatever it sent" do
      stranger = Actor.credential("u-2", [])

      for conn <- [
            post("/commands/dispatch_rig.deposit", %{account_id: "a-1", amount: "a lot"}),
            conn(:post, "/commands/dispatch_rig.deposit", "[1]")
            |> put_req_header("content-type", "application/json"),
            post("/commands/dispatch_rig.deposit", %{account_id: "a-1", amount: 1})
            |> put_req_header("x-correlation-id", "not-a-uuid")
          ] do
        refused = call(conn, stranger)
        assert {refused.status, json(refused)} == {403, %{"refused" => "missing_capability"}}
        assert asked() == [{"dispatch_rig.deposit", nil}]
      end

      assert Repo.aggregate(Event, :count) == 1
    end

    test "the control: with the capability, the problem with the request is the answer" do
      invalid =
        call(post("/commands/dispatch_rig.deposit", %{account_id: "a-1", amount: "a lot"}))

      assert {invalid.status, json(invalid)} == {422, %{"invalid" => %{"amount" => "type"}}}
      assert asked() == [{"dispatch_rig.deposit", nil}]

      valid = call(post("/commands/dispatch_rig.deposit", %{account_id: "a-1", amount: 1}))
      assert valid.status == 200
      assert asked() == [{"dispatch_rig.deposit", nil}], "asked once, by dispatch, as before"
    end

    test "a scoped command that does not decode is asked with the value as it was sent" do
      move = "dispatch_rig.move_account"
      clerk = Actor.credential("u-1", [move], %{move => %{"branch_id" => ["b-7"]}})

      body = %{account_id: "a-1", branch_id: "b-9", extra: [1]}
      undecoded = call(post("/commands/#{move}", Map.put(body, :account_id, 7)), clerk)
      assert {undecoded.status, json(undecoded)} == {403, %{"refused" => "outside_scope"}}
      assert asked() == [{move, {"branch_id", "b-9"}}]
    end

    # The Authorizer may record what it is asked (`eh_os_contract_auth` does, in a text
    # column): a value with a NUL is no value a grant holds, and is asked as none.
    test "a scoped command whose scope value is not text is asked with no value" do
      move = "dispatch_rig.move_account"
      clerk = Actor.credential("u-1", [move], %{move => %{"branch_id" => ["b-7"]}})

      conn =
        call(post("/commands/#{move}", %{account_id: "a-1", branch_id: "b-7\u0000"}), clerk)

      assert {conn.status, json(conn)} == {403, %{"refused" => "outside_scope"}}
      assert asked() == [{move, {"branch_id", nil}}]
    end

    test "a scope value past 255 bytes is asked as none, so the Authorizer never records a body" do
      move = "dispatch_rig.move_account"
      clerk = Actor.credential("u-1", [move], %{move => %{"branch_id" => ["b-7"]}})
      long = String.duplicate("b", 256)

      conn = call(post("/commands/#{move}", %{account_id: "a-1", branch_id: long}), clerk)

      assert {conn.status, json(conn)} == {403, %{"refused" => "outside_scope"}}
      assert asked() == [{move, {"branch_id", nil}}]
    end

    test "a scoped query that does not decode is asked with the value as it was sent" do
      # Without its scope parameter the query does not decode, and asks for no value
      # the grant holds: refused, as `EhOsContract.query/3` refuses it, not 422.
      missing = call(conn(:get, "/queries/#{@query}"))
      assert {missing.status, json(missing)} == {403, %{"refused" => "outside_scope"}}
      assert asked() == [{@query, {"branch_id", nil}}]
    end
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
