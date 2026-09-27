defmodule Rehmed.AuthorizationTest do
  @moduledoc """
  `Rehmed.Contracts.VisitSettlement` behind the host's door (v2 plan, EA): a bearer
  credential verified by `EhOsContract.Auth.Plug`, every command served by
  `EhOsContract.Plug` over HTTP, and every decision recorded by `EhOsContract.Auth`.

  The first test is the one `eh-os` D-34 asks of every host: each capability the
  contract declares is mapped to the entry point that serves it, and each entry
  refuses a credential without it. The rest are its controls.
  """

  use Taxvision.DataCase, async: false
  use EhOsContract.Auth.Testing

  import Phoenix.ConnTest
  import Plug.Conn

  alias EhOsContract.Event
  alias Rehmed.Contracts.VisitSettlement

  @endpoint EhOsContractHostWeb.Endpoint

  defp command(token, capability, body) do
    build_conn()
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("content-type", "application/json")
    |> post("/api/rehmed/commands/#{capability}", Jason.encode!(body))
  end

  defp entries do
    %{
      "rehmed.hand_over_visit" =>
        &command(&1, "rehmed.hand_over_visit", %{visit_id: "wizyta-anny", total: 20_000}),
      "rehmed.add_service_line" =>
        &command(&1, "rehmed.add_service_line", %{visit_id: "wizyta-anny", service_id: "usg"}),
      "rehmed.record_payment" =>
        &command(&1, "rehmed.record_payment", %{
          visit_id: "wizyta-anny",
          method: "card",
          amount: 20_000
        }),
      "rehmed.close_settlement" =>
        &command(&1, "rehmed.close_settlement", %{visit_id: "wizyta-anny"}),
      "rehmed.book_correction" =>
        &command(&1, "rehmed.book_correction", %{visit_id: "wizyta-anny", delta: -1_000})
    }
  end

  defp decisions(subject) do
    Repo.query!(
      "SELECT capability, outcome, reason FROM eh_os_contract_auth_decisions WHERE subject = $1",
      [subject]
    ).rows
  end

  test "every entry point refuses a credential without its capability" do
    assert assert_every_entry_refuses([VisitSettlement], entries()) == :ok
  end

  test "the control: a credential with the capability goes through, and has its row too" do
    token = credential("u-specjalistka", ["rehmed.hand_over_visit"])
    conn = command(token, "rehmed.hand_over_visit", %{visit_id: "wizyta-anny", total: 20_000})

    assert conn.status == 200
    assert decisions("u-specjalistka") == [["rehmed.hand_over_visit", "allowed", nil]]

    assert Repo.all(from(e in Event, select: {e.type, e.actor})) ==
             [{"visit_settlement.visit_handed_over", "actor:u-specjalistka"}]
  end

  test "a request without a credential stops at the door, before any decision" do
    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post("/api/rehmed/commands/rehmed.hand_over_visit", "{}")

    assert {conn.status, Jason.decode!(conn.resp_body)} == {401, %{"error" => "no_credential"}}
    assert Repo.query!("SELECT count(*) FROM eh_os_contract_auth_decisions").rows == [[0]]
  end

  describe "the check itself" do
    test "fails on a declared capability with no entry point, naming it" do
      entries = Map.delete(entries(), "rehmed.book_correction")

      error =
        assert_raise ExUnit.AssertionError, fn ->
          assert_every_entry_refuses([VisitSettlement], entries)
        end

      assert error.message =~ "no entry for: rehmed.book_correction"
    end

    test "fails on an entry the contract does not declare, naming it" do
      entries = Map.put(entries(), "rehmed.pay_everything", fn _token -> :ok end)

      error =
        assert_raise ExUnit.AssertionError, fn ->
          assert_every_entry_refuses([VisitSettlement], entries)
        end

      assert error.message =~ "not declared: rehmed.pay_everything"
    end

    test "fails on an entry point that never asks" do
      entries = Map.put(entries(), "rehmed.close_settlement", fn _token -> :ok end)

      error =
        assert_raise ExUnit.AssertionError, fn ->
          assert_every_entry_refuses([VisitSettlement], entries)
        end

      assert error.message =~ "the entry point for rehmed.close_settlement did not ask"
    end
  end
end
