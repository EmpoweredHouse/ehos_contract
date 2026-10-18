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
    # Taxvision.Contracts.AccountingMonth, this host's own real contract, under its id
    # (plan DD, P1a, #183) — not packages/eh_os_contract_web's invented fixture.
    assert html =~ "taxvision.accounting_month"
  end

  # Plan DD, P2w (#259): the clinic's visit, a process module, on the conformance wire.
  test "the conformance endpoint serves a process module's report", %{conn: conn} do
    conn = get(conn, "/api/eh_os_contract/conformance?process=rehmed.clinical_visit")

    assert conn.status == 200
    report = Jason.decode!(conn.resp_body)["report"]
    assert report["process"] == "rehmed.clinical_visit"

    assert [%{"promises" => [%{"promise" => "medical_event_reported_within_statutory_window"}]}] =
             report["processes"]
  end

  test "the live socket upgrade reaches the same screen as the dead render", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/dashboard/contract")
    assert html =~ "taxvision.accounting_month"
  end
end
