defmodule EhOsContract.Web.Live.GraphPreviewTest do
  @moduledoc """
  The temporary screen of plan E13b, batch 1: the renderer of `eh_os_contract_graph` on
  one document of the registry, the same document the engine gives, with its overlay
  once connected.
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

  test "draws the first contract by id, every node of its document, and nothing with a style" do
    html =
      build_conn()
      |> Access.put_actor("admin", ["eh_os_contract_admin"])
      |> get("/dashboard/graph/preview")
      |> html_response(200)

    document =
      EhOsContract.Graph.Document.contract(
        EhOsContract.Registry.contract("web_test_appeals.appeals")
      )

    assert html =~ ~s(<option value="contract:web_test_appeals.appeals" selected>)
    assert Enum.sort(cards(html)) == Enum.sort(ids(document))
    assert html |> LazyHTML.from_document() |> LazyHTML.query("main [style]") |> Enum.count() == 0
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

    assert Enum.sort(cards(html)) ==
             Enum.sort(ids(EhOsContract.Graph.Document.contract(contract)))

    # The overlay is of this document, so its numbers are drawn: zeros, in a test database.
    assert html =~ ~s(<span class="ehg-count">×0</span>)
    refute html =~ "another version of this document"

    [domain | _] = EhOsContract.Registry.domains()
    view |> form("#document-select", document: "domain:" <> inspect(domain)) |> render_change()

    domain_document =
      EhOsContract.Graph.Document.domain(domain, EhOsContract.Registry.contracts())

    assert Enum.sort(cards(render(view))) == Enum.sort(ids(domain_document))
  end
end
