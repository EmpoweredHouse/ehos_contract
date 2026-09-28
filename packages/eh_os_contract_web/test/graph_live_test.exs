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

    # The screen opens on the v2 process, though the v1 one's label sorts first: its
    # declared shape in the first panel, its contract's full graph with the log in the
    # second — the steps, and the actor issuing them.
    assert html =~ "event_case_opened"
    assert html =~ "command_open_case --&gt;"
    assert html =~ "actor_case_officer --&gt; command_open_case"
    assert html =~ "Declared versus observed, this process"
  end

  test "two processes of one name in two contracts are each reachable, a v1 one with its own panels" do
    # The v2 fixture and its v1 original both name their process `handling`.
    {:ok, view, _html} =
      build_conn()
      |> Access.put_actor("admin", ["eh_os_contract_admin"])
      |> live("/dashboard/graph")

    v1 = "#{inspect(EhOsContract.Web.TestHost.Fixtures.V1.CaseHandling)}:handling"
    html = render_change(view, "select_process", %{"process" => v1})

    assert html =~ "flowchart TB"
    assert html =~ "Declared versus observed, every contract"

    v2 = "#{inspect(EhOsContract.Web.TestHost.Fixtures.CaseHandling)}:handling"
    html = render_change(view, "select_process", %{"process" => v2})
    assert html =~ "Declared versus observed, this process"
  end

  test "no process declared anywhere says so, and draws only the overlay diagram" do
    html =
      render_component(&Graph.render/1, %{
        eh_os_contract_web_access: :all,
        eh_os_contract_web_base_path: "/dashboard",
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
        eh_os_contract_web_access: :read_only,
        eh_os_contract_web_base_path: "/dashboard",
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
