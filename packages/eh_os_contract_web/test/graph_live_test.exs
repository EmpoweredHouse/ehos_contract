defmodule EhOsContract.Web.Live.GraphTest do
  @moduledoc """
  The Graph screen through the real router: one explorer per registered domain
  (`EhOsContract.GraphRenderer.Explorer`, plan DD, stage G1, #297), whose pictures are the
  renderer's views of the engine's `graph.v1` documents, loaded by
  `EhOsContract.Web.GraphLoader` when the reader enters them. A `render/1` case covers a
  host with no domain, no database required.
  """

  use EhOsContract.Web.TestHost.DataCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias EhOsContract.Graph.{Document, Overlay}
  alias EhOsContract.GraphRenderer.View
  alias EhOsContract.Web.Live.Graph
  alias EhOsContract.Web.TestHost.Access

  @endpoint EhOsContract.Web.TestHost.Endpoint
  @domain "EhOsContract.Web.TestHost.Fixtures.Domain"

  defp live_graph do
    {:ok, view, _html} =
      build_conn()
      |> Access.put_actor("admin", ["eh_os_contract_admin"])
      |> live("/dashboard/graph")

    render_async(view)
    view
  end

  defp explorer(view), do: ~s([id="graph-#{@domain}"])

  defp page(view), do: view |> render() |> LazyHTML.from_fragment()

  # The cards the explorer's canvas draws now, by the ids the hook lays out.
  defp cards(view),
    do:
      view
      |> page()
      |> LazyHTML.query(explorer(view) <> " button.ehg-card")
      |> LazyHTML.attribute("data-ehg-node")

  defp drawn(document, spec, overlay \\ nil),
    do: document |> View.build(spec, overlay) |> Map.fetch!(:nodes) |> Enum.map(& &1.id)

  defp modules, do: EhOsContract.Registry.contracts() ++ EhOsContract.Registry.processes()

  defp open(view, card, words) do
    view |> element(explorer(view) <> ~s( button[data-ehg-node="#{card}"])) |> render_click()
    view |> element(explorer(view) <> " button.ehg-open", words) |> render_click()
    render_async(view)
  end

  test "each domain gets an explorer that starts at its system, the log over it" do
    view = live_graph()
    domain = EhOsContract.Web.TestHost.Fixtures.Domain

    assert render(view) =~ "Access: all"
    assert has_element?(view, explorer(view))

    document = Document.domain(domain, modules())
    assert cards(view) == drawn(document, :system, Overlay.domain(domain, modules()))
    assert "process:web_test_host.case_run" in cards(view)
  end

  # The EHOS Console draws the same explorer from the JSON API: the dashboard's loader
  # answers with the documents the API serves, and overlays of the same documents.
  test "the dashboard's loader gives the documents the API serves" do
    served =
      build_conn()
      |> Access.put_actor("admin", ["eh_os_contract_read"])
      |> Plug.Conn.put_req_header("accept", "application/json")

    for {ref, path} <- [
          {{:domain, @domain}, "/api/graph/domain/" <> @domain},
          {{:contract, "web_test_host.case_handling"}, "/api/graph/web_test_host.case_handling"},
          {{:process, "web_test_host.case_run"}, "/api/graph/process/web_test_host.case_run"}
        ] do
      {:ok, document} = EhOsContract.Web.GraphLoader.document(ref, [])
      {:ok, overlay} = EhOsContract.Web.GraphLoader.overlay(ref, [])

      assert Jason.decode!(get(served, path).resp_body) == document
      assert overlay["document_digest"] == document["digest"]
      assert Jason.decode!(get(served, path <> "/overlay").resp_body)["nodes"] == overlay["nodes"]
    end

    assert EhOsContract.Web.GraphLoader.document({:contract, "none.such"}, []) ==
             {:error, :not_found}
  end

  test "the static render draws no picture and reads no log until the reader is connected" do
    html =
      build_conn()
      |> Access.put_actor("admin", ["eh_os_contract_admin"])
      |> get("/dashboard/graph")
      |> html_response(200)
      |> LazyHTML.from_document()

    assert html |> LazyHTML.query(".ehg-explorer") |> Enum.count() >= 1
    assert html |> LazyHTML.query(".ehg-card") |> Enum.count() == 0
    assert Enum.empty?(LazyHTML.query(html, "main [style]"))
  end

  test "a contract opens from the system, and its unit's lifecycle is a switch" do
    view = live_graph()
    contract = EhOsContract.Registry.contract("web_test_host.case_handling")
    document = Document.contract(contract)

    open(view, "contract:web_test_host.case_handling", "Open this contract")
    assert cards(view) == drawn(document, :contract, Overlay.contract(contract))

    [unit] = document["nodes"]["unit"]

    view
    |> element(explorer(view) <> ~s( [data-ehg-group="#{unit["id"]}"] button.ehg-group-title))
    |> render_click()

    view |> element(explorer(view) <> " button.ehg-open", "Open this unit") |> render_click()
    assert cards(view) == drawn(document, {:unit, unit["id"]})

    view |> element(explorer(view) <> " .ehg-lenses button", "Lifecycle") |> render_click()

    assert cards(view) ==
             drawn(document, {:lifecycle, unit["id"]}, Overlay.contract(contract))
  end

  test "the processes are the other viewpoint" do
    view = live_graph()
    view |> element(explorer(view) <> " .ehg-tab", "Processes") |> render_click()

    view
    |> element(explorer(view) <> " .ehg-places button", "web_test_host.case_run")
    |> render_click()

    render_async(view)

    assert "process:web_test_host.case_run" in cards(view)
  end

  test "the actors under the domain's level, a row opening the actor's panel" do
    view = live_graph()

    view |> element(explorer(view) <> " .ehg-actors button", "Case officer") |> render_click()
    assert view |> element(explorer(view) <> " .ehg-panel h4") |> render() =~ "Case officer"
  end

  test "every canvas is the renderer's, and nothing has a style" do
    view = live_graph()
    html = page(view)

    for canvas <- LazyHTML.query(html, ".ehg") |> Enum.to_list() do
      assert LazyHTML.attribute(canvas, "phx-hook") == ["EhOsContractGraph"]
    end

    assert Enum.empty?(LazyHTML.query(html, "[style]"))
  end

  test "a malformed event is ignored, and the page lives on" do
    view = live_graph()
    render_change(view, "select", %{"nothing" => "here"})
    assert has_element?(view, explorer(view))
  end

  test "no domain registered says so" do
    html =
      render_component(&Graph.render/1, %{
        eh_os_contract_web_access: :all,
        eh_os_contract_web_base_path: "/dashboard",
        domains: []
      })

    assert html =~ "No domain is registered."
  end
end
