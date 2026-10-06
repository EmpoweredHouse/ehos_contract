defmodule EhOsContract.Web.Live.GraphTest do
  @moduledoc """
  Same split as `ContractStatusTest`: one test through the real router
  proves `EhOsContract.Registry`/`EhOsContract.Graph` are wired for real and that both
  Mermaid strings actually reach the page; the `render/1` cases below it
  exercise the contract-selector logic with hand-built assigns, no contract
  or database required.
  """

  use EhOsContract.Web.TestHost.DataCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias EhOsContract.Web.Live.Graph
  alias EhOsContract.Web.TestHost.Access

  @endpoint EhOsContract.Web.TestHost.Endpoint

  test "mounting through the real router draws both diagrams for a real contract" do
    {:ok, view, _html} =
      build_conn()
      |> Access.put_actor("admin", ["eh_os_contract_admin"])
      |> live("/dashboard/graph")

    # The first contract by id is selected on mount; this one is chosen.
    html =
      render_change(view, "select_contract", %{"contract" => "web_test_host.case_handling"})

    assert html =~ "Access: all"
    assert html =~ "web_test_host.case_handling — Case handling"
    assert html =~ ~s(id="declared-graph")
    assert html =~ ~s(id="overlay-graph")

    # The selected contract: its process's declared shape in the first panel, the
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

    # Plan LC4b: the case declares a lifecycle, drawn beside it with the log over it.
    assert html =~ ~s(id="lifecycle-graph-case")
    assert html =~ "Lifecycle, declared versus observed"
    assert html =~ "Declared versus observed, this contract"
    assert html =~ "Declared shape of its process"
  end

  # The static render, before the socket connects: the first contract by id, drawn
  # without the log over its lifecycles.
  test "the dead render draws the first contract by id" do
    html =
      build_conn()
      |> Access.put_actor("admin", ["eh_os_contract_admin"])
      |> get("/dashboard/graph")
      |> html_response(200)

    assert html =~ ~s(<option value="web_test_appeals.appeals" selected>)
    assert html =~ ~s(id="overlay-graph")
  end

  test "an id the page did not list keeps the selection" do
    {:ok, view, _html} =
      build_conn()
      |> Access.put_actor("admin", ["eh_os_contract_admin"])
      |> live("/dashboard/graph")

    html = render_change(view, "select_contract", %{"contract" => "nobody.knows"})
    assert html =~ ~r/value="web_test_appeals.appeals"[^>]*selected/
    assert html =~ ~s(id="overlay-graph")
  end

  test "two contracts whose processes share a name are each reachable, by id" do
    # Both fixtures name their process `handling`; the selector keys by the contract's
    # id (plan DD, P1b, #186), so each is reachable.
    {:ok, view, _html} =
      build_conn()
      |> Access.put_actor("admin", ["eh_os_contract_admin"])
      |> live("/dashboard/graph")

    html = render_change(view, "select_contract", %{"contract" => "web_test_appeals.appeals"})
    assert html =~ "event_appeal_lodged"
    refute html =~ "event_case_opened"

    html =
      render_change(view, "select_contract", %{"contract" => "web_test_host.case_handling"})

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
        contracts: [],
        selected: nil,
        declared_mermaid: nil,
        overlay_mermaid: "flowchart LR"
      })

    assert html =~ ~s(id="map-graph-bare")
    refute html =~ ~s(id="system-graph-bare")
  end

  test "no contract registered says so, and draws no diagram" do
    html =
      render_component(&Graph.render/1, %{
        eh_os_contract_web_access: :all,
        eh_os_contract_web_base_path: "/dashboard",
        domains: [],
        units: [],
        contracts: [],
        selected: nil,
        declared_mermaid: nil,
        overlay_mermaid: nil
      })

    assert html =~ "No contract is registered."
    refute html =~ ~s(id="declared-graph")
    refute html =~ ~s(id="overlay-graph")
  end

  # Plan DD, P1b (#186): a contract without a process is listed and can be selected; its
  # process's shape is not drawn, its contract graph is.
  test "the selected contract's option is marked, and one without a process is listed" do
    html =
      render_component(&Graph.render/1, %{
        eh_os_contract_web_access: :read_only,
        eh_os_contract_web_base_path: "/dashboard",
        domains: [],
        units: [],
        contracts: [
          %{contract: nil, id: "shop.cases", process: %{name: :handling, label: "Case handling"}},
          %{contract: nil, id: "shop.stock", process: nil}
        ],
        selected: "shop.stock",
        declared_mermaid: nil,
        overlay_mermaid: "flowchart LR"
      })

    assert html =~ ~s(value="shop.stock" selected>)
    refute html =~ ~s(value="shop.cases" selected>)
    assert html =~ "shop.cases — Case handling"
    refute html =~ ~s(id="declared-graph")
    assert html =~ ~s(id="overlay-graph")
    assert html =~ "Access: read only"
  end
end
