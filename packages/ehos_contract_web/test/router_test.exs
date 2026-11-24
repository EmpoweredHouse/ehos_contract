defmodule EhosContract.Web.RouterTest do
  # `async: false`: the admin-access tests below mount EhosContract.Web.Live.ContractStatus
  # for real, which queries EhosContract.Web.TestHost.Repo from the LiveView's own
  # process — a shared sandbox connection is what lets that process borrow this
  # test's transaction, the same reason EhosContract.ReportTest in packages/ehos_contract
  # uses `async: false`.
  use EhosContract.Web.TestHost.DataCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias EhosContract.Web.TestHost.Access

  @endpoint EhosContract.Web.TestHost.Endpoint

  setup do
    {:ok, conn: build_conn()}
  end

  test "the bare mount path redirects to the contract status screen, before any access check",
       %{conn: conn} do
    conn = get(conn, "/dashboard")
    assert redirected_to(conn) == "/dashboard/contract"
  end

  test "the redirect carries the query string, not just the path", %{conn: conn} do
    conn = get(conn, "/dashboard?since=2026-01-01")
    assert redirected_to(conn) == "/dashboard/contract?since=2026-01-01"
  end

  test "a caller the resolver does not know is redirected where the host said, before the LiveView ever mounts",
       %{conn: conn} do
    conn = get(conn, "/dashboard/contract")
    assert redirected_to(conn) == "/"
  end

  test "a role that maps to neither :all nor :read_only is redirected too", %{conn: conn} do
    conn =
      conn
      |> Access.put_actor("someone", ["unrelated_role"])
      |> get("/dashboard/contract")

    assert redirected_to(conn) == "/"
  end

  test "ehos_contract_admin gets a dead render with :all access", %{conn: conn} do
    conn =
      conn
      |> Access.put_actor("admin", ["ehos_contract_admin"])
      |> get("/dashboard/contract")

    assert html_response(conn, 200) =~ "Access: all"
  end

  test "on_mount enforces the same decision across the live socket upgrade", %{conn: conn} do
    conn = Access.put_actor(conn, "admin", ["ehos_contract_admin"])
    {:ok, _view, html} = live(conn, "/dashboard/contract")
    assert html =~ "Access: all"
  end

  test "an unknown caller cannot open the live socket", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/dashboard/contract")
  end

  # A screen mounted without the access hook must fail before it renders anything:
  # only the hook sets the assigns each render reads first. That kept the dashboard
  # closed when Phoenix LiveView before 1.2.14 let a client skip a live_session's
  # on_mount hooks (EEF-CVE-2026-126334, #660).
  for screen <- [EhosContract.Web.Live.ContractStatus, EhosContract.Web.Live.Graph] do
    test "#{inspect(screen)} mounted without the access hook fails before it renders", %{
      conn: conn
    } do
      error = assert_raise KeyError, fn -> live_isolated(conn, unquote(screen)) end
      assert error.key in [:ehos_contract_web_base_path, :ehos_contract_web_access]
    end
  end

  describe "mounted in a scope with a path of its own" do
    test "the bare mount path redirects under the scope's prefix", %{conn: conn} do
      assert conn |> get("/admin/dashboard") |> redirected_to() == "/admin/dashboard/contract"

      assert conn |> get("/admin/dashboard?since=2026-01-01") |> redirected_to() ==
               "/admin/dashboard/contract?since=2026-01-01"
    end

    test "the screens link to each other under the prefix", %{conn: conn} do
      conn =
        conn
        |> Access.put_actor("admin", ["ehos_contract_admin"])
        |> get("/admin/dashboard/contract")

      html = html_response(conn, 200)
      assert html =~ ~s(href="/admin/dashboard/graph")
      refute html =~ ~s(href="/dashboard/graph")
    end

    test "the resolver is given the path with its prefix, on a page and over the API",
         %{conn: conn} do
      conn = Access.put_actor(conn, "auditor", ["admin_area"])

      assert html_response(get(conn, "/admin/dashboard/contract"), 200) =~ "Access: read only"
      assert redirected_to(get(conn, "/dashboard/contract")) == "/"

      api = Plug.Conn.put_req_header(conn, "accept", "application/json")
      assert get(api, "/admin/api/model").status == 200
      assert get(api, "/api/model").status == 403
    end

    test "a connected screen links under the prefix too", %{conn: conn} do
      conn = Access.put_actor(conn, "admin", ["ehos_contract_admin"])
      {:ok, _view, html} = live(conn, "/admin/dashboard/contract")
      assert html =~ ~s(href="/admin/dashboard/graph")
    end
  end

  describe "mounted in a scope with an alias" do
    test "the screens and the API are the package's modules, not the alias's", %{conn: conn} do
      conn = Access.put_actor(conn, "admin", ["ehos_contract_admin"])

      assert conn |> get("/aliased/dashboard") |> redirected_to() == "/aliased/dashboard/contract"
      assert html_response(get(conn, "/aliased/dashboard/contract"), 200) =~ "Access: all"

      api = Plug.Conn.put_req_header(conn, "accept", "application/json")
      assert get(api, "/aliased/api/model").status == 200
    end
  end

  test "a mount path with a trailing slash gives the same paths as one without", %{conn: conn} do
    assert conn |> get("/slashed") |> redirected_to() == "/slashed/contract"
  end
end
