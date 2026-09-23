defmodule PnsPrototypeWebTest do
  @moduledoc """
  The real host, mounted for real (PLAN.md, dopisek 23 sierpnia (8)) —
  proof that `PNS.Web.Router.pns_dashboard/2` works against
  `pns_prototype`'s own `Taxvision.Repo` and real contracts, not just
  `packages/pns_web`'s own test host and its invented fixture.
  """

  use Taxvision.DataCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint PnsPrototypeWeb.Endpoint

  setup do
    {:ok, conn: build_conn()}
  end

  test "the bare mount path redirects to the contract status screen", %{conn: conn} do
    conn = get(conn, "/dashboard")
    assert redirected_to(conn) == "/dashboard/contract"
  end

  test "the contract status screen renders this host's real contracts", %{conn: conn} do
    html = conn |> get("/dashboard/contract") |> html_response(200)

    # `PnsPrototypeWeb.Resolver` lets everyone in read-only: this host has no
    # login, and says so rather than inheriting a default.
    assert html =~ "Access: read only"
    # Taxvision.Contracts.AccountingMonth, this host's own real contract —
    # not packages/pns_web's invented CaseHandling fixture.
    assert html =~ "AccountingMonth"
  end

  test "the live socket upgrade reaches the same screen as the dead render", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/dashboard/contract")
    assert html =~ "AccountingMonth"
  end
end
