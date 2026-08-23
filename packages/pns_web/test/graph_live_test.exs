defmodule PNS.Web.Live.GraphTest do
  @moduledoc """
  Same split as `ContractStatusTest`: one test through the real router
  proves `PNS.Registry`/`PNS.Graph` are wired for real and that both
  Mermaid strings actually reach the page; the `render/1` cases below it
  exercise the process-selector logic with hand-built assigns, no contract
  or database required.
  """

  use PNS.Web.TestHost.DataCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias PNS.Web.Live.Graph
  alias PNS.Web.TestHost.TestToken

  @endpoint PNS.Web.TestHost.Endpoint

  test "mounting through the real router draws both diagrams for a real contract" do
    conn =
      build_conn()
      |> TestToken.put_actor("admin", ["pns_admin"])
      |> get("/pns/graph")

    html = html_response(conn, 200)

    assert html =~ "Access: all"
    assert html =~ "Case handling"
    assert html =~ "flowchart TB"
    assert html =~ "flowchart LR"
    assert html =~ ~s(id="declared-graph")
    assert html =~ ~s(id="overlay-graph")
  end

  test "no process declared anywhere says so, and draws only the overlay diagram" do
    html =
      render_component(&Graph.render/1, %{
        pns_web_access: :all,
        pns_web_base_path: "/pns",
        processes: [],
        selected: nil,
        declared_mermaid: nil,
        overlay_mermaid: "flowchart LR"
      })

    assert html =~ "No process is declared in any registered contract."
    refute html =~ ~s(id="declared-graph")
    assert html =~ ~s(id="overlay-graph")
  end

  test "the selected process's option is marked, others are not" do
    html =
      render_component(&Graph.render/1, %{
        pns_web_access: :read_only,
        pns_web_base_path: "/pns",
        processes: [
          %{contract: nil, name: :handling, label: "Case handling"},
          %{contract: nil, name: :billing, label: "Billing"}
        ],
        selected: :billing,
        declared_mermaid: "flowchart TB",
        overlay_mermaid: "flowchart LR"
      })

    assert html =~ ~s(value="billing" selected>)
    refute html =~ ~s(value="handling" selected>)
    assert html =~ "Access: read only"
  end
end
