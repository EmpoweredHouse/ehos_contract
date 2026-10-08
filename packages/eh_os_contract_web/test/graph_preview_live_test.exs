defmodule EhOsContract.Web.Live.GraphPreviewTest do
  @moduledoc """
  The temporary screen of plan E13b, batches 1 and 3: the renderer of
  `eh_os_contract_graph` drawing one view of one document of the registry, the same
  document the engine gives, with its overlay once connected, and under it the Mermaid
  diagram of the same picture.
  """

  use EhOsContract.Web.TestHost.DataCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias EhOsContract.Web.TestHost.Access

  @endpoint EhOsContract.Web.TestHost.Endpoint

  defp cards(html),
    do:
      html
      |> LazyHTML.from_document()
      |> LazyHTML.query("[data-ehg-node]")
      |> LazyHTML.attribute("data-ehg-node")

  defp ids(document), do: for({_kind, group} <- document["nodes"], node <- group, do: node["id"])

  defp drawn(document, spec),
    do:
      document
      |> EhOsContract.GraphRenderer.View.build(spec)
      |> Map.fetch!(:nodes)
      |> Enum.map(& &1.id)

  defp mermaid(html),
    do:
      html
      |> LazyHTML.from_document()
      |> LazyHTML.query("pre.mermaid")
      |> LazyHTML.attribute("data-graph")

  test "draws the first view of the first contract by id, its picture in Mermaid, and nothing with a style" do
    html =
      build_conn()
      |> Access.put_actor("admin", ["eh_os_contract_admin"])
      |> get("/dashboard/graph/preview")
      |> html_response(200)

    contract = EhOsContract.Registry.contract("web_test_appeals.appeals")
    document = EhOsContract.Graph.Document.contract(contract)
    [{spec, _title} | _] = EhOsContract.GraphRenderer.View.views(document)

    assert html =~ ~s(<option value="contract:web_test_appeals.appeals" selected>)
    assert Enum.sort(cards(html)) == Enum.sort(drawn(document, spec))
    assert [diagram] = mermaid(html)
    assert diagram =~ "flowchart"
    assert html |> LazyHTML.from_document() |> LazyHTML.query("main [style]") |> Enum.count() == 0
  end

  test "draws every node of the document as the test bed, without a diagram" do
    {:ok, view, _html} =
      build_conn()
      |> Access.put_actor("admin", ["eh_os_contract_admin"])
      |> live("/dashboard/graph/preview?document=contract:web_test_appeals.appeals&view=all")

    document =
      EhOsContract.Graph.Document.contract(
        EhOsContract.Registry.contract("web_test_appeals.appeals")
      )

    html = render(view)
    assert Enum.sort(cards(html)) == Enum.sort(ids(document))
    assert mermaid(html) == []
  end

  test "picks a contract or a domain, and lays the overlay over it once connected" do
    {:ok, view, _html} =
      build_conn()
      |> Access.put_actor("admin", ["eh_os_contract_admin"])
      |> live("/dashboard/graph/preview")

    view
    |> form("#document-select", document: "contract:web_test_host.case_handling")
    |> render_change()

    assert_patch(view, "/dashboard/graph/preview?document=contract%3Aweb_test_host.case_handling")

    html = render(view)
    contract = EhOsContract.Registry.contract("web_test_host.case_handling")
    document = EhOsContract.Graph.Document.contract(contract)

    [{first, _title} | _] = EhOsContract.GraphRenderer.View.views(document)
    assert Enum.sort(cards(html)) == Enum.sort(drawn(document, first))

    view
    |> form("#document-select",
      document: "contract:web_test_host.case_handling",
      view: "contract"
    )
    |> render_change()

    # The overlay is of this document, so its numbers are drawn: zeros, in a test database.
    html = render(view)
    assert Enum.sort(cards(html)) == Enum.sort(drawn(document, :contract))
    assert html =~ ~s(<span class="ehg-count">×0</span>)
    refute html =~ "another version of this document"

    [unit | _] = document["nodes"]["unit"]

    view
    |> form("#document-select",
      document: "contract:web_test_host.case_handling",
      view: "unit:" <> unit["id"]
    )
    |> render_change()

    assert Enum.sort(cards(render(view))) == Enum.sort(drawn(document, {:unit, unit["id"]}))
    assert [diagram] = mermaid(render(view))
    assert diagram =~ "flowchart LR"

    [domain | _] = EhOsContract.Registry.domains()
    view |> form("#document-select", document: "domain:" <> inspect(domain)) |> render_change()

    domain_document =
      EhOsContract.Graph.Document.domain(domain, EhOsContract.Registry.contracts())

    assert Enum.sort(cards(render(view))) == Enum.sort(drawn(domain_document, :context_map))
  end
end
