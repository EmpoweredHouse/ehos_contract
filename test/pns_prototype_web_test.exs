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

  test "no login redirects to the provisional login screen", %{conn: conn} do
    conn = get(conn, "/dashboard/contract")
    assert redirected_to(conn) == "/dashboard/login"
  end

  test "logging in as admin reaches the contract status screen with real contracts",
       %{conn: conn} do
    conn = post(conn, "/dashboard/login", %{"subject" => "reviewer", "role" => "pns_admin"})
    assert redirected_to(conn, 303) == "/dashboard/contract"

    conn = conn |> recycle() |> get("/dashboard/contract")
    html = html_response(conn, 200)

    assert html =~ "Access: all"
    # Taxvision.Contracts.AccountingMonth, this host's own real contract —
    # not packages/pns_web's invented CaseHandling fixture.
    assert html =~ "AccountingMonth"
  end

  test "logging in as read only reaches the accounts screen without the grant form",
       %{conn: conn} do
    conn = post(conn, "/dashboard/login", %{"subject" => "viewer", "role" => "pns_read"})
    conn = conn |> recycle() |> get("/dashboard/accounts")
    html = html_response(conn, 200)

    assert html =~ "Access: read only"
    refute html =~ "Invite someone"
  end

  test "the live socket upgrade enforces the same decision as the dead render",
       %{conn: conn} do
    conn = post(conn, "/dashboard/login", %{"subject" => "reviewer", "role" => "pns_admin"})
    conn = conn |> recycle()

    {:ok, _view, html} = live(conn, "/dashboard/contract")
    assert html =~ "Access: all"
  end

  test "logging out sends a subsequent visit back to the login screen", %{conn: conn} do
    conn = post(conn, "/dashboard/login", %{"subject" => "reviewer", "role" => "pns_admin"})

    conn = conn |> recycle() |> get("/dashboard/logout")
    assert redirected_to(conn) == "/dashboard/login"

    conn = conn |> recycle() |> get("/dashboard/contract")
    assert redirected_to(conn) == "/dashboard/login"
  end
end
