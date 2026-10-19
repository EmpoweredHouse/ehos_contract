defmodule EhOsContractHostWebTest do
  @moduledoc """
  The real host, mounted for real (PLAN.md, dopisek 23 sierpnia (8)) —
  proof that `EhOsContract.Web.Router.eh_os_contract_dashboard/2` works against
  `eh_os_contract_host`'s own `EhOsContractHost.Repo` and real contracts, not just
  `packages/eh_os_contract_web`'s own test host and its invented fixture.
  """

  use EhOsContractHost.DataCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint EhOsContractHostWeb.Endpoint

  setup do
    {:ok, conn: build_conn()}
  end

  test "the bare mount path redirects to the contract status screen", %{conn: conn} do
    conn = get(conn, "/dashboard")
    assert redirected_to(conn) == "/dashboard/contract"
  end

  test "the contract status screen renders this host's real contracts", %{conn: conn} do
    html = conn |> get("/dashboard/contract") |> html_response(200)

    # `EhOsContractHostWeb.Resolver` lets everyone in read-only: this host has no
    # login, and says so rather than inheriting a default.
    assert html =~ "Access: read only"
    # This host's own contracts, under their ids (plan DD, P1a, #183) — not
    # packages/eh_os_contract_web's fixture.
    assert html =~ "fulfilment.warehouse"
    assert html =~ "lending.circulation"
  end

  test "the conformance endpoint serves the library's late fee", %{conn: conn} do
    conn = get(conn, "/api/eh_os_contract/conformance?process=lending.late_fee")

    assert conn.status == 200
    report = Jason.decode!(conn.resp_body)["report"]
    assert report["process"] == "lending.late_fee"

    assert [%{"promises" => [%{"promise" => "settled_within_thirty_days"}]}] =
             report["processes"]
  end

  # Plan DD, P2w (#259): an order, a process module across three contracts, on the
  # conformance wire.
  test "the conformance endpoint serves a process module's report", %{conn: conn} do
    conn = get(conn, "/api/eh_os_contract/conformance?process=fulfilment.order")

    assert conn.status == 200
    report = Jason.decode!(conn.resp_body)["report"]
    assert report["process"] == "fulfilment.order"

    assert [%{"promises" => [%{"promise" => "dispatched_within_a_day_of_payment"}]}] =
             report["processes"]
  end

  test "the live socket upgrade reaches the same screen as the dead render", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/dashboard/contract")
    assert html =~ "fulfilment.warehouse"
  end
end
