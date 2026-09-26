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

    # The first process is the v2 one: both panels are its steps.
    assert html =~ "command_open_case --&gt; event_case_opened"
    assert html =~ "Declared versus observed, this process"
  end

  test "a v1 process keeps its declared shape and the overlay of every contract" do
    {:ok, view, _html} =
      build_conn()
      |> Access.put_actor("admin", ["eh_os_contract_admin"])
      |> live("/dashboard/graph")

    html = render_change(view, "select_process", %{"process" => "v1_handling"})

    assert html =~ "flowchart TB"
    assert html =~ "Declared versus observed, every contract"
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
        selected: :billing,
        declared_mermaid: "flowchart TB",
        overlay_mermaid: "flowchart LR"
      })

    assert html =~ ~s(value="billing" selected>)
    refute html =~ ~s(value="handling" selected>)
    assert html =~ "Access: read only"
  end
end
