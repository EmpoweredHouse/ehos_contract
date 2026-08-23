defmodule PNS.Web.RouterTest do
  # `async: false`: the admin-access tests below mount PNS.Web.Live.ContractStatus
  # for real, which queries PNS.Web.TestHost.Repo from the LiveView's own
  # process — a shared sandbox connection is what lets that process borrow this
  # test's transaction, the same reason PNS.ReportTest in packages/pns_core
  # uses `async: false`.
  use PNS.Web.TestHost.DataCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias PNS.Web.TestHost.TestToken

  @endpoint PNS.Web.TestHost.Endpoint

  setup do
    {:ok, conn: build_conn()}
  end

  test "the bare mount path redirects to the contract status screen, before any access check",
       %{conn: conn} do
    conn = get(conn, "/pns")
    assert redirected_to(conn) == "/pns/contract"
  end

  test "the redirect carries the query string, not just the path", %{conn: conn} do
    conn = get(conn, "/pns?since=2026-01-01")
    assert redirected_to(conn) == "/pns/contract?since=2026-01-01"
  end

  test "no login redirects to the provisional login, before the LiveView ever mounts",
       %{conn: conn} do
    conn = get(conn, "/pns/contract")
    assert redirected_to(conn) == "/pns/login"
  end

  test "a role that maps to neither :all nor :read_only redirects to login too", %{conn: conn} do
    conn =
      conn
      |> TestToken.put_actor("someone", ["unrelated_role"])
      |> get("/pns/contract")

    assert redirected_to(conn) == "/pns/login"
  end

  test "pns_admin gets a dead render with :all access", %{conn: conn} do
    conn =
      conn
      |> TestToken.put_actor("admin", ["pns_admin"])
      |> get("/pns/contract")

    assert html_response(conn, 200) =~ "Access: all"
  end

  test "on_mount enforces the same decision across the live socket upgrade", %{conn: conn} do
    conn = TestToken.put_actor(conn, "admin", ["pns_admin"])
    {:ok, _view, html} = live(conn, "/pns/contract")
    assert html =~ "Access: all"
  end

  test "an unauthenticated conn cannot open the live socket", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/pns/login"}}} = live(conn, "/pns/contract")
  end
end
