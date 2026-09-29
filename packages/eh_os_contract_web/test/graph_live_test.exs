defmodule EhOsContract.Web.Live.GraphTest do
  @moduledoc """
  Same split as `ContractStatusTest`: one test through the real router
  proves `EhOsContract.Registry`/`EhOsContract.Graph` are wired for real and that both
  Mermaid strings actually reach the page; the `render/1` cases below it
  exercise the process-selector logic with hand-built assigns, no contract
  or database required.
  """

  use EhOsContract.Web.TestHost.DataCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias EhOsContract.Web.Live.Graph
  alias EhOsContract.Web.TestHost.Access

  @endpoint EhOsContract.Web.TestHost.Endpoint

  test "mounting through the real router draws both diagrams for a real contract" do
    conn =
      build_conn()
      |> Access.put_actor("admin", ["eh_os_contract_admin"])
      |> get("/dashboard/graph")

    html = html_response(conn, 200)

    assert html =~ "Access: all"
    assert html =~ "Case handling"
    assert html =~ ~s(id="declared-graph")
    assert html =~ ~s(id="overlay-graph")

    # The screen opens on the process: its declared shape in the first panel, its
    # contract's full graph with the log in the second — the steps, and the actor
    # issuing them.
    assert html =~ "event_case_opened"
    assert html =~ "command_open_case --&gt;"
    assert html =~ "actor_case_officer --&gt; command_open_case"

    # Above them, the system of each domain with a v2 contract (plan EG2), with the log.
    assert html =~ "The system, declared versus observed — domain"
    assert html =~ ~r/id="system-graph-\w+"/
    assert html =~ "contract_eh_os_contract_web_test_host_fixtures_case_handling"

    # And the domain's context map, and each unit of the selected contract (28 September).
    assert html =~ "Context map — domain web_test_host"
    assert html =~ ~r/id="map-graph-web_test_host"/

    assert [unit] =
             html
             |> LazyHTML.from_document()
             |> LazyHTML.query("pre[id^=unit-graph-]")
             |> Enum.to_list()

    assert [graph] = LazyHTML.attribute(unit, "data-graph")
    assert graph =~ ~r/^flowchart LR\n    state_\w+\["/
    assert html =~ "Declared versus observed, this process"
  end

  test "two processes of one name in two contracts are each reachable" do
    # Both fixtures name their process `handling`: a key by name alone would make one
    # of them unreachable, so the selector keys by contract and name.
    {:ok, view, _html} =
      build_conn()
      |> Access.put_actor("admin", ["eh_os_contract_admin"])
      |> live("/dashboard/graph")

    appeals = "#{inspect(EhOsContract.Web.TestHost.Fixtures.Appeals)}:handling"
    html = render_change(view, "select_process", %{"process" => appeals})
    assert html =~ "event_appeal_lodged"
    refute html =~ "event_case_opened"

    cases = "#{inspect(EhOsContract.Web.TestHost.Fixtures.CaseHandling)}:handling"
    html = render_change(view, "select_process", %{"process" => cases})
    assert html =~ "event_case_opened"
  end

  # Without it LiveView's patch takes the drawn SVG out of every block on every change — a
  # process switch blanked the context map and the system too, which had not changed. The hook
  # still hears of a changed `data-graph`: LiveView updates an ignored block's attributes.
  test "every diagram block keeps what the browser drew in it across a patch" do
    html =
      build_conn()
      |> Access.put_actor("admin", ["eh_os_contract_admin"])
      |> get("/dashboard/graph")
      |> html_response(200)

    blocks = html |> LazyHTML.from_document() |> LazyHTML.query("pre.mermaid") |> Enum.to_list()

    assert length(blocks) >= 4

    for block <- blocks do
      assert LazyHTML.attribute(block, "phx-update") == ["ignore"],
             "#{inspect(LazyHTML.attribute(block, "id"))} is patched by LiveView"
    end
  end

  test "a domain with no v2 contract has its map, and no system" do
    html =
      render_component(&Graph.render/1, %{
        eh_os_contract_web_access: :all,
        eh_os_contract_web_base_path: "/dashboard",
        domains: [%{name: :bare, map: "flowchart LR", system: false}],
        units: [],
        processes: [],
        selected: nil,
        declared_mermaid: nil,
        overlay_mermaid: "flowchart LR"
      })

    assert html =~ ~s(id="map-graph-bare")
    refute html =~ ~s(id="system-graph-bare")
  end

  test "no process declared anywhere says so, and draws no process diagram" do
    html =
      render_component(&Graph.render/1, %{
        eh_os_contract_web_access: :all,
        eh_os_contract_web_base_path: "/dashboard",
        domains: [],
        units: [],
        processes: [],
        selected: nil,
        declared_mermaid: nil,
        overlay_mermaid: nil
      })

    assert html =~ "No process is declared in any registered contract."
    refute html =~ ~s(id="declared-graph")
    refute html =~ ~s(id="overlay-graph")
  end

  test "the selected process's option is marked, others are not" do
    html =
      render_component(&Graph.render/1, %{
        eh_os_contract_web_access: :read_only,
        eh_os_contract_web_base_path: "/dashboard",
        domains: [],
        units: [],
        processes: [
          %{contract: nil, name: :handling, label: "Case handling"},
          %{contract: nil, name: :billing, label: "Billing"}
        ],
        selected: "nil:billing",
        declared_mermaid: "flowchart TB",
        overlay_mermaid: "flowchart LR"
      })

    assert html =~ ~s(value="nil:billing" selected>)
    refute html =~ ~s(value="nil:handling" selected>)
    assert html =~ "Access: read only"
  end
end
