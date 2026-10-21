defmodule Lending.DoorTest do
  @moduledoc """
  The library's contracts behind the host's door: a bearer credential verified by
  `EhOsContract.Auth.Plug`, every command and query served by `EhOsContract.Plug` over
  HTTP, every decision recorded by `EhOsContract.Auth`, and the host answering for what
  is not the caller's to say. A late fee comes from the desk's tariff, and whether a
  card is suspended from the card system.
  """

  use EhOsContractHost.DataCase, async: false
  use EhOsContract.Auth.Testing

  import Phoenix.ConnTest
  import Plug.Conn

  alias EhOsContract.{Actor, Event}
  alias Lending.Contracts.{Circulation, Membership}
  alias Lending.Contracts.Circulation.Commands.LendCopy

  @contracts [Membership, Circulation]

  @endpoint EhOsContractHostWeb.Endpoint

  defp command(token, capability, body) do
    build_conn()
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("content-type", "application/json")
    |> post("/api/lending/commands/#{capability}", Jason.encode!(body))
  end

  defp query(token, capability, params) do
    build_conn()
    |> put_req_header("authorization", "Bearer " <> token)
    |> get("/api/lending/queries/#{capability}?#{params}")
  end

  defp answer(conn), do: {conn.status, Jason.decode!(conn.resp_body)}

  @loan %{loan_id: "loan-late"}
  @lend %{
    loan_id: "loan-late",
    copy_id: "copy-1",
    member_id: "member-ada",
    card_id: "card-ada",
    due_at: "2026-10-01T17:00:00Z"
  }

  # Every capability of the two contracts. The chase's notice is the process manager's
  # alone, and has none (the last test).
  defp entries do
    commands = %{
      "lending.register_member" => %{
        membership_id: "membership-ada",
        member_id: "member-ada",
        name: "Ada Lovelace",
        email: "ada@example.org"
      },
      "lending.change_email" => %{
        membership_id: "membership-ada",
        member_id: "member-ada",
        email: "ada@example.net"
      },
      "lending.withdraw_copy" => %{copy_id: "copy-1"},
      "lending.lend_copy" => @lend,
      "lending.return_copy" => @loan,
      "lending.pay_late_fee" => @loan,
      "lending.waive_late_fee" => @loan,
      "lending.place_hold" => %{copy_id: "copy-1", member_id: "member-ada"}
    }

    Map.new(commands, fn {capability, body} -> {capability, &command(&1, capability, body)} end)
    |> Map.put(
      "lending.member_contact",
      &query(&1, "lending.member_contact", "member_id=member-ada")
    )
  end

  defp decisions(subject) do
    Repo.query!(
      "SELECT capability, outcome, reason FROM eh_os_contract_auth_decisions WHERE subject = $1",
      [subject]
    ).rows
  end

  defp payloads(type),
    do:
      Repo.all(from(e in Event, where: e.type == ^type, order_by: e.position, select: e.payload))

  # A copy lent the way the desk lends it, so that the door has a loan to take back.
  defp lent(loan) do
    {:ok, _} =
      EhOsContract.dispatch(
        Circulation,
        %LendCopy{
          loan_id: loan,
          copy_id: "copy-1",
          member_id: "member-ada",
          card_id: "card-ada",
          due_at: ~U[2026-10-01 17:00:00Z]
        },
        actor: Actor.credential("librarian-una", ["lending.lend_copy"])
      )
  end

  test "every entry point refuses a credential without its capability" do
    assert assert_every_entry_refuses(@contracts, entries()) == :ok
  end

  test "a request without a credential stops at the door, before any decision" do
    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post("/api/lending/commands/lending.withdraw_copy", "{}")

    assert answer(conn) == {401, %{"error" => "no_credential"}}
    assert Repo.query!("SELECT count(*) FROM eh_os_contract_auth_decisions").rows == [[0]]
  end

  test "fields that do not fit are refused first to a credential without the capability" do
    body = %{copy_id: 7}

    stranger = credential("u-stranger", [])

    assert answer(command(stranger, "lending.withdraw_copy", body)) ==
             {403, %{"refused" => "missing_capability"}}

    assert decisions("u-stranger") == [["lending.withdraw_copy", "refused", "missing_capability"]]

    # The control: with the capability, the problem with the fields is the answer.
    librarian = credential("librarian-una", ["lending.withdraw_copy"])

    assert answer(command(librarian, "lending.withdraw_copy", body)) ==
             {422, %{"invalid" => %{"copy_id" => "type"}}}

    assert decisions("librarian-una") == [["lending.withdraw_copy", "allowed", nil]]
  end

  test "a late copy is charged the tariff's fee, which the caller may not send" do
    lent("loan-late")
    librarian = credential("librarian-una", ["lending.return_copy"])

    assert answer(command(librarian, "lending.return_copy", Map.put(@loan, :late_fee, 0))) ==
             {422, %{"invalid" => %{"late_fee" => "supplied"}}}

    assert command(librarian, "lending.return_copy", @loan).status == 200
    assert [%{"fee" => 150}] = payloads("lending.circulation.late_fee_charged")
  end

  test "a copy back on time is charged nothing" do
    lent("loan-on-time")
    librarian = credential("librarian-una", ["lending.return_copy"])

    assert command(librarian, "lending.return_copy", %{loan_id: "loan-on-time"}).status == 200
    assert payloads("lending.circulation.copy_returned") != []
    assert payloads("lending.circulation.late_fee_charged") == []
  end

  test "a loan the tariff does not know is the host's to answer, and nothing is written" do
    librarian = credential("librarian-una", ["lending.return_copy"])

    assert answer(command(librarian, "lending.return_copy", %{loan_id: "loan-elsewhere"})) ==
             {503, %{"error" => "not_supplied"}}

    assert Repo.aggregate(Event, :count) == 0
  end

  test "a loan reads the card shown from the card system" do
    librarian = credential("librarian-una", ["lending.lend_copy"])

    assert command(librarian, "lending.lend_copy", @lend).status == 200
    assert [%{"card_id" => "card-ada"}] = payloads("lending.circulation.copy_lent")

    # A suspended card is the business's refusal; a card the system does not have names
    # nothing, and is the field's problem.
    suspended = %{@lend | loan_id: "loan-bob", member_id: "member-bob", card_id: "card-bob"}

    assert answer(command(librarian, "lending.lend_copy", suspended)) ==
             {422, %{"rejected" => "suspended_card_borrows_nothing"}}

    unknown = %{@lend | loan_id: "loan-eve", card_id: "card-eve"}

    assert answer(command(librarian, "lending.lend_copy", unknown)) ==
             {422, %{"invalid" => %{"card_id" => "unknown"}}}

    assert length(payloads("lending.circulation.copy_lent")) == 1
  end

  test "what only the chase does is not a door, whatever the credential names" do
    # A credential granted it by mistake could otherwise record a notice nobody sent.
    token = credential("u-mistaken", ["lending.send_overdue_notice"])

    assert command(token, "lending.send_overdue_notice", @loan).status == 404
    assert Repo.all(from(e in Event, select: e.type)) == []
  end

  # The helper every host audits its door with refuses each way a door can be wrong.
  describe "the check itself" do
    test "fails on a declared capability with no entry point, naming it" do
      entries = Map.delete(entries(), "lending.pay_late_fee")

      error =
        assert_raise ExUnit.AssertionError, fn ->
          assert_every_entry_refuses(@contracts, entries)
        end

      assert error.message =~ "no entry for: lending.pay_late_fee"
    end

    test "fails on an entry the contract does not declare, naming it" do
      entries = Map.put(entries(), "lending.forgive_everything", fn _token -> :ok end)

      error =
        assert_raise ExUnit.AssertionError, fn ->
          assert_every_entry_refuses(@contracts, entries)
        end

      assert error.message =~ "not declared: lending.forgive_everything"
    end

    test "fails on an entry point that never asks" do
      entries = Map.put(entries(), "lending.waive_late_fee", fn _token -> :ok end)

      error =
        assert_raise ExUnit.AssertionError, fn ->
          assert_every_entry_refuses(@contracts, entries)
        end

      assert error.message =~ "the entry point for lending.waive_late_fee did not ask"
    end
  end
end
