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

  alias PNS.Web.TestHost.Access

  @endpoint PNS.Web.TestHost.Endpoint

  setup do
    {:ok, conn: build_conn() |> put_req_header("accept", "application/json")}
  end

  describe "who gets an answer" do
    test "a caller the resolver refuses gets JSON, not a redirect", %{conn: conn} do
      # A redirect is a datum only a browser can use. An API client following one
      # would fetch the host's login page and try to parse it as JSON.
      conn = get(conn, "/pns/api/conformance")

      assert conn.status == 403
      assert Jason.decode!(conn.resp_body) == %{"error" => "forbidden"}
      assert get_resp_header(conn, "location") == []
    end

    test "a read-only actor gets the report", %{conn: conn} do
      conn = conn |> Access.put_actor("u-1", ["pns_read"]) |> get("/pns/api/conformance")

      assert conn.status == 200
      assert %{"schema" => "pns.conformance.v1"} = Jason.decode!(conn.resp_body)
    end

    test "and so does an admin, identically", %{conn: conn} do
      # `:read_only` and `:all` both pass and neither is redacted. Redacting for one
      # would be this package forming an opinion about how sensitive a client's own
      # data is.
      admin = conn |> Access.put_actor("u-2", ["pns_admin"]) |> get("/pns/api/conformance")

      reader =
        build_conn() |> Access.put_actor("u-1", ["pns_read"]) |> get("/pns/api/conformance")

      assert admin.status == 200
      assert Jason.decode!(admin.resp_body)["report"] == Jason.decode!(reader.resp_body)["report"]
    end
  end

  describe "what comes back" do
    setup %{conn: conn} do
      {:ok, conn: Access.put_actor(conn, "u-1", ["pns_read"])}
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

  describe "the generated specification" do
    setup %{conn: conn} do
      {:ok, conn: Access.put_actor(conn, "u-1", ["pns_read"])}
    end

    test "the index lists every contract with its digest", %{conn: conn} do
      conn = get(conn, "/pns/api/asyncapi")

      assert conn.status == 200
      %{"contracts" => contracts} = Jason.decode!(conn.resp_body)
      assert length(contracts) == length(PNS.Registry.contracts())
      assert Enum.all?(contracts, &(byte_size(&1["digest"]) == 12))
    end

    test "a document is served, and its ETag is its digest", %{conn: conn} do
      name = PNS.Registry.contracts() |> List.first() |> inspect()
      conn = get(conn, "/pns/api/asyncapi/#{name}")

      assert conn.status == 200
      document = Jason.decode!(conn.resp_body)
      assert document["asyncapi"] == "3.0.0"

      # Served twice on purpose: a consumer comparing what an instance claims
      # against what its build recorded can do it with a HEAD and no body.
      assert get_resp_header(conn, "etag") == [~s("#{document["info"]["x-pns-digest"]}")]
    end

    test "an unknown contract is 404, not an empty document", %{conn: conn} do
      conn = get(conn, "/pns/api/asyncapi/Not.A.Contract")

      assert conn.status == 404
    end

    test "it is not public", %{conn: _conn} do
      # It names every event, every field and every label in the client's own words.
      # That is a map of their business, not "just a schema".
      conn = build_conn() |> put_req_header("accept", "application/json")

      assert get(conn, "/pns/api/asyncapi").status == 403
      assert get(conn, "/pns/api/asyncapi/Anything").status == 403
    end
  end

  describe "the screens still work" do
    test "the dashboard's HTML routes are untouched by the API mount" do
      conn =
        build_conn()
        |> Access.put_actor("u-3", ["pns_admin"])
        |> get("/pns/contract")

      assert conn.status == 200
    end
  end
end
