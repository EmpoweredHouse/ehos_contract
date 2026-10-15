defmodule EhOsContract.Web.Live.GraphTest do
  @moduledoc """
  Same split as `ContractStatusTest`: tests through the real router prove
  `EhOsContract.Registry` and the engine's `graph.v1` documents are wired for real and
  that each picture is the renderer's view of them; the `render/1` cases below exercise
  the contract-selector logic with hand-built assigns, no database required.
  """

  use EhOsContract.Web.TestHost.DataCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias EhOsContract.Graph.{Document, Overlay}
  alias EhOsContract.GraphRenderer.View
  alias EhOsContract.Web.Live.Graph
  alias EhOsContract.Web.TestHost.Access
  alias EhOsContract.Web.TestHost.Fixtures.AppealsDomain

  @endpoint EhOsContract.Web.TestHost.Endpoint

  defp live_graph do
    {:ok, view, _html} =
      build_conn()
      |> Access.put_actor("admin", ["eh_os_contract_admin"])
      |> live("/dashboard/graph")

    view
  end

  defp canvas(html, id), do: html |> LazyHTML.from_document() |> LazyHTML.query(~s([id="#{id}"]))

  # The cards a canvas draws, by the ids the hook lays out.
  defp cards(html, id),
    do:
      html
      |> canvas(id)
      |> LazyHTML.query("[data-ehg-node]")
      |> LazyHTML.attribute("data-ehg-node")

  defp drawn(document, spec, overlay \\ nil),
    do: document |> View.build(spec, overlay) |> Map.fetch!(:nodes) |> Enum.map(& &1.id)

  test "mounting through the real router draws every picture of a real contract as its view" do
    view = live_graph()

    # The first contract by id is selected on mount; this one is chosen.
    html =
      render_change(view, "select", %{"selected" => "contract:web_test_host.case_handling"})

    assert html =~ "Access: all"
    assert html =~ ~r/value="contract:web_test_host.case_handling"[^>]*selected/

    contract = EhOsContract.Registry.contract("web_test_host.case_handling")
    document = Document.contract(contract)
    overlay = Overlay.contract(contract)

    # Its full graph with the log laid over it once connected: zeros, in a test database.
    # A contract declares no process (plan DD, P2h, #221), so no declared shape of one.
    refute html =~ ~s(id="declared-graph")
    assert html =~ "Declared versus observed, this contract"
    assert cards(html, "overlay-graph") == drawn(document, :contract, overlay)

    assert html |> canvas("overlay-graph") |> LazyHTML.query(".ehg-count") |> Enum.count() > 0

    # Each unit, and the case's lifecycle beside it with the log over it (plan LC4b).
    [unit] = document["nodes"]["unit"]
    assert html =~ "aggregate case — Case"
    assert cards(html, "unit-graph-" <> unit["id"]) == drawn(document, {:unit, unit["id"]})
    assert html =~ "Lifecycle, declared versus observed"

    assert cards(html, "lifecycle-graph-" <> unit["id"]) ==
             drawn(document, {:lifecycle, unit["id"]}, overlay)

    # Above them, each domain's context map, and its system with the log (plan EG2).
    domain = EhOsContract.Web.TestHost.Fixtures.Domain

    domain_document =
      Document.domain(
        domain,
        EhOsContract.Registry.contracts() ++ EhOsContract.Registry.processes()
      )

    assert html =~ "Context map — domain web_test_host"
    assert cards(html, "map-graph-web_test_host") == drawn(domain_document, :context_map)
    assert html =~ "The system, declared versus observed — domain web_test_host"
    assert cards(html, "system-graph-web_test_host") == drawn(domain_document, :system)
  end

  # Plan DD, P2e (#220): the screen is given the document the API serves, process
  # modules included, so a digest names one document wherever it is read.
  test "each domain's document and overlay are the ones the API serves" do
    view = live_graph()
    %{domains: domains} = :sys.get_state(view.pid).socket.assigns

    served =
      build_conn()
      |> Access.put_actor("admin", ["eh_os_contract_read"])
      |> Plug.Conn.put_req_header("accept", "application/json")

    for %{document: document, overlay: overlay} <- domains do
      path = "/api/graph/domain/" <> document["domain"]

      assert Jason.decode!(get(served, path).resp_body) == document
      assert overlay["document_digest"] == document["digest"]

      assert Jason.decode!(get(served, path <> "/overlay").resp_body)["nodes"] ==
               overlay["nodes"]
    end

    assert Enum.any?(domains, &(&1.document["nodes"]["process"] != []))
  end

  # Point 2 of the working plan (`PLAN.md`, "Szczegóły ekranu Graph"): the domain's actors under its map, a row opening the
  # actor's panel, though the map does not draw actors.
  test "the actors under a domain's map, a row opening the actor's panel" do
    view = live_graph()

    assert has_element?(view, ~s(.ehg-actors button[phx-target='[id="map-graph-web_test_host"]']))

    view |> element(".ehg-actors button", "Case officer") |> render_click()

    assert view
           |> element("#map-graph-web_test_host .ehg-panel h4")
           |> render() =~ "Case officer"
  end

  # The static render, before the socket connects: the first contract by id, its pictures
  # drawn declared, without reading the log.
  test "the dead render draws the first contract by id, without the log" do
    html =
      build_conn()
      |> Access.put_actor("admin", ["eh_os_contract_admin"])
      |> get("/dashboard/graph")
      |> html_response(200)

    assert html =~ ~s(<option value="contract:web_test_appeals.appeals" selected>)
    assert html =~ ~s(id="overlay-graph")
    refute html =~ "ehg-count"
  end

  test "an id the page did not list keeps the selection" do
    view = live_graph()

    html = render_change(view, "select", %{"selected" => "contract:nobody.knows"})
    assert html =~ ~r/value="contract:web_test_appeals.appeals"[^>]*selected/
    assert html =~ ~s(id="overlay-graph")
  end

  test "a malformed event is ignored, and the page lives on" do
    view = live_graph()

    for {event, params} <- [{"select", %{}}, {"select", %{"selected" => ["x"]}}, {"nope", %{}}] do
      html = render_change(view, event, params)
      assert html =~ ~r/value="contract:web_test_appeals.appeals"[^>]*selected/
    end

    assert Process.alive?(view.pid)
  end

  test "two registered contracts are each reachable, by id" do
    # The selector keys by the contract's id (plan DD, P1b, #186).
    view = live_graph()

    html = render_change(view, "select", %{"selected" => "contract:web_test_appeals.appeals"})
    assert "event:web_test_appeals.appeals:appeal_lodged" in cards(html, "overlay-graph")
    refute "event:web_test_host.case_handling:case_opened" in cards(html, "overlay-graph")

    html =
      render_change(view, "select", %{"selected" => "contract:web_test_host.case_handling"})

    assert "event:web_test_host.case_handling:case_opened" in cards(html, "overlay-graph")
  end

  # The renderer's hook draws each picture; LiveView leaves the arrows it draws alone.
  test "every picture is the renderer's canvas, and nothing has a style" do
    html =
      build_conn()
      |> Access.put_actor("admin", ["eh_os_contract_admin"])
      |> get("/dashboard/graph")
      |> html_response(200)
      |> LazyHTML.from_document()

    canvases = LazyHTML.query(html, ".ehg") |> Enum.to_list()
    assert length(canvases) >= 4
    assert Enum.empty?(LazyHTML.query(html, "main [style]"))

    for canvas <- canvases do
      assert LazyHTML.attribute(canvas, "phx-hook") == ["EhOsContractGraph"]

      assert canvas |> LazyHTML.query("svg.ehg-arrows") |> LazyHTML.attribute("phx-update") ==
               ["ignore"]
    end
  end

  defp assigns(overrides) do
    Map.merge(
      %{
        eh_os_contract_web_access: :all,
        eh_os_contract_web_base_path: "/dashboard",
        domains: [],
        pickable: [],
        selected: nil,
        kind: nil,
        document: nil,
        overlay: nil,
        units: []
      },
      overrides
    )
  end

  test "a domain with no v2 contract has its map, and no system" do
    document = Document.domain(AppealsDomain, [])

    html =
      render_component(
        &Graph.render/1,
        assigns(%{
          domains: [
            %{name: "bare", document: document, system?: false, overlay: nil}
          ]
        })
      )

    assert html =~ ~s(id="map-graph-bare")
    refute html =~ ~s(id="system-graph-bare")
  end

  test "no contract registered says so, and draws no picture of one" do
    html = render_component(&Graph.render/1, assigns(%{}))

    assert html =~ "No contract or process module is registered."
    refute html =~ ~s(id="declared-graph")
    refute html =~ ~s(id="overlay-graph")
  end

  # Plan DD, P1b (#186) and P2e (#220): every contract and process module is listed by its
  # id, in a group of its kind, and can be selected.
  test "the selected option is marked, contracts and processes apart" do
    document = Document.contract(EhOsContract.Registry.contract("web_test_appeals.appeals"))

    pick = fn kind, id -> %{kind: kind, module: nil, id: id, value: "#{kind}:#{id}"} end

    html =
      render_component(
        &Graph.render/1,
        assigns(%{
          eh_os_contract_web_access: :read_only,
          pickable: [
            pick.(:contract, "shop.cases"),
            pick.(:contract, "shop.stock"),
            pick.(:process, "shop.stock")
          ],
          selected: "contract:shop.stock",
          kind: :contract,
          document: document
        })
      )

    assert html =~ ~s(value="contract:shop.stock" selected>)
    refute html =~ ~s(value="contract:shop.cases" selected>)
    assert html =~ ~s(value="contract:shop.cases">)
    assert html =~ ~s(value="process:shop.stock">)

    groups = html |> LazyHTML.from_fragment() |> LazyHTML.query("optgroup")
    assert LazyHTML.attribute(groups, "label") == ["Contracts", "Processes"]

    refute html =~ ~s(id="process-graph")
    assert html =~ ~s(id="overlay-graph")
    assert html =~ "Access: read only"
  end

  # Plan DD, P2e (#220): a process module is reached by its id, though a contract may have
  # it too, and its picture is drawn with the log over it.
  test "selecting a process module draws its picture with its overlay, and no units" do
    view = live_graph()

    html = render_change(view, "select", %{"selected" => "process:web_test_host.case_run"})
    assert html =~ ~r/value="process:web_test_host.case_run"[^>]*selected/
    assert html =~ "Declared versus observed, this process"
    refute html =~ ~s(id="overlay-graph")
    refute html =~ ~s(id="unit-graph-)

    process = EhOsContract.Registry.process("web_test_host.case_run")
    document = Document.process(process)
    overlay = Overlay.process(process)

    assert cards(html, "process-graph") == drawn(document, :process, overlay)
    assert "process:web_test_host.case_run" in cards(html, "process-graph")

    # Its runs, from the log, on the process: none in a test database.
    assert html
           |> canvas("process-graph")
           |> LazyHTML.query(~s([data-ehg-node="process:web_test_host.case_run"] .ehg-count))
           |> LazyHTML.text() == "×0"

    # And back to a contract.
    html = render_change(view, "select", %{"selected" => "contract:web_test_host.case_handling"})
    assert html =~ ~s(id="overlay-graph")
    refute html =~ ~s(id="process-graph")
  end

  test "the system view draws each process module of the domain" do
    html =
      build_conn()
      |> Access.put_actor("admin", ["eh_os_contract_admin"])
      |> get("/dashboard/graph")
      |> html_response(200)

    assert "process:web_test_host.case_run" in cards(html, "system-graph-web_test_host")
  end
end
