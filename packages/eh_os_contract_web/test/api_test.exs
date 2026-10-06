defmodule EhOsContract.Web.ApiTest do
  @moduledoc """
  Stage 5.8: **the conformance report as data, over HTTP.**

  Until now the only way to read anything this engine computes was a mix task in a
  terminal, which means exactly one kind of consumer. The screens and this share one
  access decision — the host's `EhOsContract.Web.Resolver` — deliberately: a host writes the
  rule once, and a transport does not get to soften it.
  """

  use EhOsContract.Web.TestHost.DataCase, async: false

  import Phoenix.ConnTest
  import Plug.Conn, only: [put_req_header: 3, get_resp_header: 2]

  alias EhOsContract.Web.TestHost.Access

  @endpoint EhOsContract.Web.TestHost.Endpoint

  # A conformance request names the contract it asks about.
  @contract "/api/conformance?contract=web_test_host.case_handling"

  setup do
    {:ok, conn: build_conn() |> put_req_header("accept", "application/json")}
  end

  describe "who gets an answer" do
    test "a caller the resolver refuses gets JSON, not a redirect", %{conn: conn} do
      # A redirect is a datum only a browser can use. An API client following one
      # would fetch the host's login page and try to parse it as JSON.
      conn = get(conn, "/api/conformance")

      assert conn.status == 403
      assert Jason.decode!(conn.resp_body) == %{"error" => "forbidden"}
      assert get_resp_header(conn, "location") == []
    end

    test "a read-only actor gets the report", %{conn: conn} do
      conn = conn |> Access.put_actor("u-1", ["eh_os_contract_read"]) |> get(@contract)

      assert conn.status == 200
      assert %{"schema" => "eh_os_contract.conformance.v3"} = Jason.decode!(conn.resp_body)
    end

    test "and so does an admin, identically", %{conn: conn} do
      # `:read_only` and `:all` both pass and neither is redacted. Redacting for one
      # would be this package forming an opinion about how sensitive a client's own
      # data is.
      admin = conn |> Access.put_actor("u-2", ["eh_os_contract_admin"]) |> get(@contract)

      reader =
        build_conn()
        |> Access.put_actor("u-1", ["eh_os_contract_read"])
        |> get(@contract)

      assert admin.status == 200
      assert Jason.decode!(admin.resp_body)["report"] == Jason.decode!(reader.resp_body)["report"]
    end
  end

  describe "what comes back" do
    setup %{conn: conn} do
      {:ok, conn: Access.put_actor(conn, "u-1", ["eh_os_contract_read"])}
    end

    test "a named contract is served", %{conn: conn} do
      contract = EhOsContract.Registry.contracts() |> List.first()
      id = EhOsContract.Model.fetch(contract).id
      conn = get(conn, "/api/conformance?contract=#{id}")

      assert conn.status == 200
      report = Jason.decode!(conn.resp_body)["report"]
      assert report["contract"] == id
      assert report["module"] == inspect(contract)
    end

    # Plan DD, P1a (#183): a contract is named by its id; its module's name is not one.
    test "a module's name is not a contract's name", %{conn: conn} do
      module = EhOsContract.Registry.contracts() |> List.first() |> inspect()
      conn = get(conn, "/api/conformance?contract=#{module}")

      assert conn.status == 400
      assert Jason.decode!(conn.resp_body)["detail"] =~ "unknown contract"
    end

    test "without `contract=`, several registered contracts are a bad request", %{conn: conn} do
      # The host registers two, and a report of whichever came first would answer a
      # question nobody asked.
      conn = get(conn, "/api/conformance")

      assert conn.status == 400
      assert Jason.decode!(conn.resp_body)["detail"] =~ "several contracts are registered"
    end

    test "an unknown contract is a bad request, not a crash", %{conn: conn} do
      conn = get(conn, "/api/conformance?contract=Not.A.Contract")

      assert conn.status == 400
      assert Jason.decode!(conn.resp_body)["detail"] =~ "unknown contract"
    end

    test "an unparseable period is a bad request naming which one", %{conn: conn} do
      conn = get(conn, @contract <> "&since=yesterday")

      assert conn.status == 400
      assert Jason.decode!(conn.resp_body)["detail"] =~ "since"
    end
  end

  describe "the generated specification" do
    setup %{conn: conn} do
      {:ok, conn: Access.put_actor(conn, "u-1", ["eh_os_contract_read"])}
    end

    test "the index lists every contract with its digest", %{conn: conn} do
      conn = get(conn, "/api/asyncapi")

      assert conn.status == 200
      %{"contracts" => contracts} = Jason.decode!(conn.resp_body)

      assert Enum.map(contracts, & &1["contract"]) ==
               EhOsContract.Registry.contracts()
               |> Enum.map(&EhOsContract.Model.fetch(&1).id)
               |> Enum.sort()

      assert Enum.all?(contracts, &(byte_size(&1["digest"]) == 12))
    end

    test "a document is served, and its ETag is its digest", %{conn: conn} do
      name = EhOsContract.Model.fetch(EhOsContract.Registry.contracts() |> List.first()).id
      conn = get(conn, "/api/asyncapi/#{name}")

      assert conn.status == 200
      document = Jason.decode!(conn.resp_body)
      assert document["asyncapi"] == "3.0.0"
      assert document["operations"] == %{}

      # Served twice on purpose: a consumer comparing what an instance claims
      # against what its build recorded can do it with a HEAD and no body.
      assert get_resp_header(conn, "etag") == [
               ~s("#{document["info"]["x-eh-os-contract-digest"]}")
             ]
    end

    test "an unknown contract is 404, not an empty document", %{conn: conn} do
      conn = get(conn, "/api/asyncapi/Not.A.Contract")

      assert conn.status == 404
    end

    test "it is not public", %{conn: _conn} do
      # It names every event, every field and every label in the client's own words.
      # That is a map of their business, not "just a schema".
      conn = build_conn() |> put_req_header("accept", "application/json")

      assert get(conn, "/api/asyncapi").status == 403
      assert get(conn, "/api/asyncapi/Anything").status == 403
    end
  end

  describe "the exported model" do
    setup %{conn: conn} do
      {:ok, conn: Access.put_actor(conn, "u-1", ["eh_os_contract_read"])}
    end

    test "the index names its schema and lists v2 contracts only", %{conn: conn} do
      conn = get(conn, "/api/model")

      assert conn.status == 200

      assert %{"schema" => "eh_os_contract.model-index.v1", "contracts" => contracts} =
               Jason.decode!(conn.resp_body)

      assert Enum.map(contracts, & &1["contract"]) ==
               EhOsContract.Registry.contracts()
               |> Enum.map(&EhOsContract.Model.fetch(&1).id)
               |> Enum.sort()

      assert Enum.all?(contracts, &(byte_size(&1["digest"]) == 12))
    end

    test "a model document is served with its digest as the ETag", %{conn: conn} do
      name = EhOsContract.Model.fetch(EhOsContract.Registry.contracts() |> List.first()).id
      conn = get(conn, "/api/model/#{name}")

      assert conn.status == 200
      document = Jason.decode!(conn.resp_body)
      assert document["schema"] == "eh_os_contract.model.v1"
      assert document["contract"]["id"] == name
      assert get_resp_header(conn, "etag") == [~s("#{document["digest"]}")]
    end

    test "an unknown or unauthenticated request receives no model", %{conn: conn} do
      assert get(conn, "/api/model/Not.A.Contract").status == 404

      public = build_conn() |> put_req_header("accept", "application/json")
      assert get(public, "/api/model").status == 403
      assert get(public, "/api/model/Anything").status == 403
    end
  end

  describe "the generated command-and-query API" do
    setup %{conn: conn} do
      {:ok, conn: Access.put_actor(conn, "u-1", ["eh_os_contract_read"])}
    end

    test "the index lists v2 contracts with OpenAPI digests", %{conn: conn} do
      conn = get(conn, "/api/openapi")

      assert conn.status == 200
      %{"contracts" => contracts} = Jason.decode!(conn.resp_body)

      assert Enum.map(contracts, & &1["contract"]) ==
               EhOsContract.Registry.contracts()
               |> Enum.map(&EhOsContract.Model.fetch(&1).id)
               |> Enum.sort()

      assert Enum.all?(contracts, &(byte_size(&1["digest"]) == 12))
    end

    test "a document is served with relative plug paths and its digest as the ETag", %{conn: conn} do
      name = "web_test_host.case_handling"
      conn = get(conn, "/api/openapi/#{name}")

      assert conn.status == 200
      document = Jason.decode!(conn.resp_body)
      assert document["openapi"] == "3.1.2"
      assert Map.has_key?(document["paths"], "/commands/web_test_host.open_case")

      assert get_resp_header(conn, "etag") == [
               ~s("#{document["info"]["x-eh-os-contract-digest"]}")
             ]
    end

    test "unknown and unauthenticated requests receive no specification", %{conn: conn} do
      assert get(conn, "/api/openapi/Not.A.Contract").status == 404

      public = build_conn() |> put_req_header("accept", "application/json")
      assert get(public, "/api/openapi").status == 403
      assert get(public, "/api/openapi/Anything").status == 403
    end
  end

  describe "the screens still work" do
    test "the dashboard's HTML routes are untouched by the API mount" do
      conn =
        build_conn()
        |> Access.put_actor("u-3", ["eh_os_contract_admin"])
        |> get("/dashboard/contract")

      assert conn.status == 200
    end
  end
end
