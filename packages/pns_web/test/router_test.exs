defmodule PNS.Web.RouterTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias PNS.Web.TestHost.TestToken

  @endpoint PNS.Web.TestHost.Endpoint

  setup do
    {:ok, conn: build_conn()}
  end

  test "no login redirects before the LiveView ever mounts", %{conn: conn} do
    conn = get(conn, "/pns")
    assert redirected_to(conn) == "/"
  end

  test "a role that maps to neither :all nor :read_only redirects", %{conn: conn} do
    conn =
      conn
      |> TestToken.put_actor("someone", ["unrelated_role"])
      |> get("/pns")

    assert redirected_to(conn) == "/"
  end

  test "pns_admin gets a dead render with :all access", %{conn: conn} do
    conn =
      conn
      |> TestToken.put_actor("admin", ["pns_admin"])
      |> get("/pns")

    assert html_response(conn, 200) =~ "access: :all"
  end

  test "on_mount enforces the same decision across the live socket upgrade", %{conn: conn} do
    conn = TestToken.put_actor(conn, "admin", ["pns_admin"])
    {:ok, _view, html} = live(conn, "/pns")
    assert html =~ "access: :all"
  end

  test "an unauthenticated conn cannot open the live socket", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/pns")
  end
end
