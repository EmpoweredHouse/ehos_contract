defmodule PNS.Web.ApiTest do
  @moduledoc """
  Stage 5.8: **the conformance report as data, over HTTP.**

  Until now the only way to read anything this engine computes was a mix task in a
  terminal, which means exactly one kind of consumer. The screens and this share one
  access decision — the host's `PNS.Web.Resolver` — deliberately: a host writes the
  rule once, and a transport does not get to soften it.
  """

  use PNS.Web.TestHost.DataCase, async: false

  import Phoenix.ConnTest
  import Plug.Conn, only: [put_req_header: 3, get_resp_header: 2]

  alias PNS.Web.TestHost.TestToken

  @endpoint PNS.Web.TestHost.Endpoint

  setup do
    {:ok, conn: build_conn() |> put_req_header("accept", "application/json")}
  end

  describe "who gets an answer" do
    test "an unauthenticated request is refused as JSON, not redirected", %{conn: conn} do
      # A redirect is a datum only a browser can use. An API client following one
      # would fetch a login page and try to parse it as JSON.
      conn = get(conn, "/pns/api/conformance")

      assert conn.status == 403
      assert Jason.decode!(conn.resp_body) == %{"error" => "forbidden"}
      assert get_resp_header(conn, "location") == []
    end

    test "a request with no session at all does not crash", %{conn: conn} do
      # **The regression this stage exists to have found.**
      # `PNS.Web.Plug.Authenticate` fell through to `get_session/2`, which raises
      # when `fetch_session` has not run — so in a session-less API pipeline it
      # crashed on exactly the unauthenticated request the endpoint most needs to
      # refuse cleanly. A 500 here, not a 403, is that bug returning.
      conn = get(conn, "/pns/api/conformance")

      assert conn.status == 403
    end

    test "a read-only actor gets the report", %{conn: conn} do
      conn = conn |> TestToken.put_actor("u-1", ["pns_read"]) |> get("/pns/api/conformance")

      assert conn.status == 200
      assert %{"schema" => "pns.conformance.v1"} = Jason.decode!(conn.resp_body)
    end

    test "and so does an admin, identically", %{conn: conn} do
      # `:read_only` and `:all` both pass and neither is redacted. Redacting for one
      # would be this package forming an opinion about how sensitive a client's own
      # data is.
      admin = conn |> TestToken.put_actor("u-2", ["pns_admin"]) |> get("/pns/api/conformance")
      reader = build_conn() |> TestToken.put_actor("u-1", ["pns_read"]) |> get("/pns/api/conformance")

      assert admin.status == 200
      assert Jason.decode!(admin.resp_body)["report"] == Jason.decode!(reader.resp_body)["report"]
    end
  end

  describe "what comes back" do
    setup %{conn: conn} do
      {:ok, conn: TestToken.put_actor(conn, "u-1", ["pns_read"])}
    end

    test "a named contract is served", %{conn: conn} do
      contract = PNS.Registry.contracts() |> List.first() |> inspect()
      conn = get(conn, "/pns/api/conformance?contract=#{contract}")

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["report"]["contract"] == contract
    end

    test "an unknown contract is a bad request, not a crash", %{conn: conn} do
      conn = get(conn, "/pns/api/conformance?contract=Not.A.Contract")

      assert conn.status == 400
      assert Jason.decode!(conn.resp_body)["detail"] =~ "unknown contract"
    end

    test "an unparseable period is a bad request naming which one", %{conn: conn} do
      conn = get(conn, "/pns/api/conformance?since=yesterday")

      assert conn.status == 400
      assert Jason.decode!(conn.resp_body)["detail"] =~ "since"
    end
  end

  describe "the screens still work" do
    test "the dashboard's HTML routes are untouched by the API mount" do
      conn =
        build_conn()
        |> TestToken.put_actor("u-3", ["pns_admin"])
        |> get("/pns/contract")

      assert conn.status == 200
    end
  end
end
